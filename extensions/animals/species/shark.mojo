# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sharks: procedural-animals' `species/shark/`.

Two variants share one swimmer rig and one sculpt: the great white
(the default) and the blacktip reef shark. Every length is a fraction of
the total length `TL`, read from each variant's outline table. The body
is a dense chain of teardrop sections. The fins are fleshy airfoils: a
thin full outline with thicker cores toward the root. The lower jaw is
its own surface, and rows of triangular teeth line both jaws.

The original meshes each variant at `TL / 415` times the variant's cell
factor. Here the reference shark is built with `TL` equal to one over
that factor, so one `CELL` serves both, and the `size` trait scales it to
the variant's real length.
"""

from extensions.animals.coat import (
    KERATIN,
    SCALES,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    palette_of,
    srgb,
)
from extensions.sdf.ids import (
    BoneId,
    SurfacePart,
)
from extensions.animals.parts import (
    BODY,
    JAW,
    TEETH,
)
from extensions.animals.kit import EyeSpec
from extensions.animals.noise import cells3, fbm3
from extensions.animals.options import (
    ADULT,
    ANY_AGE,
    JUVENILE,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.swimmer_rig import (
    Profile,
    fin_plane_v,
    offset_poly,
    spine_name,
    swimmer_bones,
)
from extensions.animals.traits import Traits, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    length,
    normalize,
    smoothstep,
)
from extensions.animals.warp import scale_about_warp
from std.math import cos, exp, floor, pi, pow, sin, sqrt

# The shark's head origin moves with the variant, so the eye is placed
# from the reference origin instead.
comptime HEAD_O = V3(0.0, 0.0, 0.0)
# The finest cell, at the `HERO` tier, for the reference shark: TL / 415.
comptime CELL = 1.0 / 415.0

# The variants, in procedural-animals' order.
comptime WHITE = 0
comptime BLACKTIP = 1

comptime D2R = pi / 180.0


def shark_variant_names() -> List[String]:
    """Return the shark's variants.

    Returns:
        The great white and the blacktip reef shark.
    """
    return [String("white"), "blacktip"]


struct _Geo(Movable):
    # The original's `sharkGeo`: outline lookups in reference meters, the
    # landmarks and the fin outlines.
    var white: Bool
    var tl: Float64
    var real_tl: Float64
    var cell_k: Float64
    var prof: Profile
    var girth_k: Float64
    var fin_k: Float64
    var dorsal_k: Float64
    var pec_k: Float64
    var tail_k: Float64
    var axis_y: Float64
    var z0: Float64
    var pc: Float64
    var occ: Float64
    var eye_u: Float64
    var eye_e: Float64
    var snout_y: Float64
    var u_f: Float64
    var u_c: Float64
    var e_c: Float64
    var jaw_depth: Float64
    var smile: Float64
    var gill_u0: Float64
    var gill_u1: Float64
    var gill_e0: Float64
    var gill_e1: Float64
    var gill_lean: Float64
    var nostril_u: Float64
    var nostril_e: Float64
    var d1_u: Float64
    var d1_poly: List[Float64]
    var d1_thick: Float64
    var d2_u: Float64
    var d2_poly: List[Float64]
    var anal_u: Float64
    var anal_poly: List[Float64]
    var c_up: Float64
    var c_low: Float64
    var c_ua: Float64
    var c_la: Float64
    var c_fork: Float64
    var c_notch: Float64
    var c_keel: Float64
    var c_thick: Float64
    var p_u: Float64
    var p_e: Float64
    var p_len: Float64
    var p_droop: Float64
    var p_abduct: Float64
    var p_thick: Float64
    var p_poly: List[Float64]
    var v_u: Float64
    var v_len: Float64
    var v_abduct: Float64
    var v_thick: Float64
    var v_poly: List[Float64]
    var clasper: Float64
    var y_f: Float64
    var y_c: Float64
    var eye_y: Float64
    var eye_r: Float64
    var eye_z: Float64
    var eye_x: Float64
    var head_o: V3
    var pit: V3

    def __init__(
        out self,
        variant: Int,
        girth_k: Float64,
        fin_k: Float64,
        dorsal_k: Float64,
        pec_k: Float64,
        tail_k: Float64,
        low_lobe_k: Float64,
    ):
        self.white = variant == WHITE
        self.girth_k = girth_k
        self.fin_k = fin_k
        self.dorsal_k = dorsal_k
        self.pec_k = pec_k
        self.tail_k = tail_k
        if self.white:
            self.real_tl = 4.5
            self.cell_k = 1.0
            self.prof = Profile(
                [
                    0.004, 0.004, 0.003, 0.005,
                    0.02, 0.019, 0.013, 0.02,
                    0.045, 0.034, 0.028, 0.04,
                    0.08, 0.048, 0.043, 0.059,
                    0.13, 0.062, 0.057, 0.074,
                    0.19, 0.075, 0.07, 0.081,
                    0.26, 0.085, 0.08, 0.084,
                    0.33, 0.091, 0.083, 0.085,
                    0.4, 0.09, 0.08, 0.082,
                    0.47, 0.083, 0.071, 0.074,
                    0.55, 0.07, 0.057, 0.062,
                    0.63, 0.053, 0.042, 0.047,
                    0.7, 0.039, 0.031, 0.036,
                    0.75, 0.029, 0.023, 0.03,
                    0.8, 0.022, 0.019, 0.027,
                ]
            )  # fmt: skip
            self.occ = 0.21
            self.eye_u = 0.066
            self.eye_e = 0.3
            self.eye_r = 0.0058
            self.snout_y = 0.004
            self.u_f = 0.047
            self.u_c = 0.1
            self.e_c = -0.42
            self.jaw_depth = 0.03
            self.smile = 0.35
            self.gill_u0 = 0.185
            self.gill_u1 = 0.258
            self.gill_e0 = -0.62
            self.gill_e1 = 0.5
            self.gill_lean = 0.012
            self.nostril_u = 0.028
            self.nostril_e = -0.62
            self.pc = 0.8
            self.d1_u = 0.365
            self.d1_poly = [
                0, -0.02, 0, 0, 0.018, 0.04, 0.035, 0.078, 0.049, 0.103,
                0.058, 0.108, 0.063, 0.1, 0.064, 0.072, 0.072, 0.04,
                0.088, 0.016, 0.108, 0.004, 0.1, -0.02,
            ]  # fmt: skip
            self.d1_thick = 0.014
            self.d2_u = 0.71
            self.d2_poly = [
                0, -0.01, 0, 0, 0.006, 0.012, 0.012, 0.016, 0.016, 0.01,
                0.026, 0.002, 0.024, -0.01,
            ]  # fmt: skip
            self.anal_u = 0.725
            self.anal_poly = [
                0, 0.01, 0, 0, 0.006, -0.012, 0.012, -0.016, 0.016, -0.01,
                0.026, -0.002, 0.024, 0.01,
            ]  # fmt: skip
            self.c_up = 0.245
            self.c_low = 0.185
            self.c_ua = 40.0 * D2R
            self.c_la = -46.0 * D2R
            self.c_fork = 0.085
            self.c_notch = 0.0
            self.c_keel = 0.012
            self.c_thick = 0.0105
            self.p_u = 0.262
            self.p_e = -0.55
            self.p_len = 0.19
            self.p_droop = 26.0
            self.p_abduct = 50.0
            self.p_thick = 0.0095
            self.p_poly = [
                -0.02, 0.05, 0.25, 0.042, 0.55, 0.026, 0.8, 0.004, 0.93,
                -0.014, 1.0, -0.03, 0.985, -0.034, 0.9, -0.033, 0.8, -0.031,
                0.55, -0.034, 0.3, -0.042, 0.12, -0.05, 0.02, -0.058, -0.02,
                -0.05,
            ]  # fmt: skip
            self.v_u = 0.6
            self.v_len = 0.07
            self.v_abduct = 26.0
            self.v_thick = 0.008
            self.v_poly = [
                -0.05, 0.035, 0.4, 0.028, 0.8, 0.01, 1.0, -0.006, 0.9,
                -0.018, 0.4, -0.02, -0.05, -0.024,
            ]  # fmt: skip
            self.clasper = 0.075
        else:
            self.real_tl = 1.3
            self.cell_k = 1.15
            self.prof = Profile(
                [
                    0.004, 0.004, 0.003, 0.009,
                    0.02, 0.014, 0.011, 0.025,
                    0.045, 0.024, 0.021, 0.036,
                    0.08, 0.034, 0.031, 0.045,
                    0.13, 0.045, 0.042, 0.053,
                    0.19, 0.056, 0.052, 0.058,
                    0.26, 0.068, 0.064, 0.062,
                    0.33, 0.077, 0.07, 0.065,
                    0.4, 0.078, 0.069, 0.064,
                    0.47, 0.073, 0.062, 0.059,
                    0.55, 0.058, 0.048, 0.048,
                    0.63, 0.046, 0.037, 0.038,
                    0.7, 0.034, 0.027, 0.027,
                    0.75, 0.025, 0.02, 0.02,
                    0.78, 0.021, 0.018, 0.017,
                ]
            )  # fmt: skip
            self.occ = 0.2
            self.eye_u = 0.07
            self.eye_e = 0.28
            self.eye_r = 0.0078
            self.snout_y = 0.002
            self.u_f = 0.052
            self.u_c = 0.098
            self.e_c = -0.55
            self.jaw_depth = 0.026
            self.smile = 0.15
            self.gill_u0 = 0.2
            self.gill_u1 = 0.25
            self.gill_e0 = -0.45
            self.gill_e1 = 0.25
            self.gill_lean = 0.006
            self.nostril_u = 0.03
            self.nostril_e = -0.6
            self.pc = 0.785
            self.d1_u = 0.39
            self.d1_poly = [
                0, -0.02, 0, 0, 0.024, 0.042, 0.046, 0.08, 0.064, 0.11,
                0.074, 0.118, 0.08, 0.11, 0.08, 0.078, 0.086, 0.044, 0.1,
                0.02, 0.122, 0.006, 0.112, -0.02,
            ]  # fmt: skip
            self.d1_thick = 0.011
            self.d2_u = 0.72
            self.d2_poly = [
                0, -0.01, 0, 0, 0.01, 0.024, 0.017, 0.034, 0.023, 0.03,
                0.026, 0.012, 0.04, 0.004, 0.036, -0.01,
            ]  # fmt: skip
            self.anal_u = 0.735
            self.anal_poly = [
                0, 0.01, 0, 0, 0.01, -0.024, 0.017, -0.032, 0.023, -0.028,
                0.026, -0.012, 0.04, -0.004, 0.036, 0.01,
            ]  # fmt: skip
            self.c_up = 0.265
            self.c_low = 0.145
            self.c_ua = 29.0 * D2R
            self.c_la = -52.0 * D2R
            self.c_fork = 0.07
            self.c_notch = 0.035
            self.c_keel = 0.0
            self.c_thick = 0.0075
            self.p_u = 0.28
            self.p_e = -0.62
            self.p_len = 0.175
            self.p_droop = 30.0
            self.p_abduct = 52.0
            self.p_thick = 0.0085
            self.p_poly = [
                -0.02, 0.045, 0.25, 0.04, 0.55, 0.027, 0.8, 0.007, 0.93,
                -0.01, 1.0, -0.026, 0.985, -0.031, 0.9, -0.03, 0.8, -0.029,
                0.55, -0.03, 0.3, -0.036, 0.12, -0.042, 0.02, -0.05, -0.02,
                -0.044,
            ]  # fmt: skip
            self.v_u = 0.6
            self.v_len = 0.075
            self.v_abduct = 28.0
            self.v_thick = 0.0065
            self.v_poly = [
                -0.05, 0.035, 0.4, 0.028, 0.8, 0.01, 1.0, -0.008, 0.9,
                -0.02, 0.4, -0.022, -0.05, -0.026,
            ]  # fmt: skip
            self.clasper = 0.085
        self.tl = 1.0 / self.cell_k
        self.axis_y = 0.155 * self.tl
        self.z0 = 0.45 * self.tl
        self.c_up = self.c_up * tail_k
        self.c_low = self.c_low * tail_k * low_lobe_k
        self.y_f = 0.0
        self.y_c = 0.0
        self.eye_y = 0.0
        self.eye_z = 0.0
        self.eye_x = 0.0
        self.head_o = V3(0.0, 0.0, 0.0)
        self.pit = V3(0.0, 0.0, 0.0)
        self.y_f = self.bot(self.u_f) + 0.0015 * self.tl
        self.y_c = self.yc(self.u_c) + self.e_c * self.hd(self.u_c)
        self.eye_y = self.yc(self.eye_u) + self.eye_e * self.hd(self.eye_u)
        self.eye_r = self.eye_r * self.tl
        self.eye_z = self.z(self.eye_u)
        self.eye_x = (
            self.surf_x(self.eye_u, self.eye_y)
            + 0.0033 * self.tl
            - 0.3 * self.eye_r
        )
        self.head_o = V3(0.0, self.eye_y, self.eye_z)
        self.pit = V3(0.0, self.yc(self.pc), self.z(self.pc))

    def z(self, u: Float64) -> Float64:
        return self.z0 - u * self.tl

    def u(self, z: Float64) -> Float64:
        return (self.z0 - z) / self.tl

    def girth(self, u: Float64) -> Float64:
        var inside = u > 0.1 and u < 0.72
        return (
            1.0
            + (self.girth_k - 1.0)
            * sin(pi * (u - 0.1) / 0.62) if inside else 1.0
        )

    def yc(self, u: Float64) -> Float64:
        return (
            self.axis_y
            + (self.prof.at(u, 1) - self.prof.at(u, 2)) / 2.0 * self.tl
        )

    def hd(self, u: Float64) -> Float64:
        return (
            (self.prof.at(u, 1) + self.prof.at(u, 2))
            / 2.0
            * self.tl
            * self.girth(u)
        )

    def hw(self, u: Float64) -> Float64:
        return self.prof.at(u, 3) * self.tl * self.girth(u)

    def top(self, u: Float64) -> Float64:
        return self.yc(u) + self.hd(u)

    def bot(self, u: Float64) -> Float64:
        return self.yc(u) - self.hd(u)

    def wk(self, u: Float64) -> Float64:
        var t1 = clamp((u - 0.08) / 0.14, 0.0, 1.0)
        var t2 = clamp((u - 0.66) / 0.12, 0.0, 1.0)
        var s1 = t1 * t1 * (3.0 - 2.0 * t1)
        var s2 = t2 * t2 * (3.0 - 2.0 * t2)
        return 0.95 - 0.11 * s1 + 0.09 * s2

    def surf_x(self, u: Float64, y: Float64) -> Float64:
        # The teardrop section: a narrow upper ellipse united with a wide,
        # flat lower one.
        var hd = max(1e-6, self.hd(u))
        var hw = self.hw(u)
        var e = (y - self.yc(u)) / hd
        var eb = (y - (self.yc(u) - 0.3 * hd)) / (0.7 * hd)
        return max(
            hw * self.wk(u) * sqrt(max(0.0, 1.0 - e * e)),
            hw * sqrt(max(0.0, 1.0 - eb * eb)),
        )

    def belly(self, u: Float64, f: Float64) -> Float64:
        return (
            self.yc(u)
            - 0.3 * self.hd(u)
            - 0.7 * self.hd(u) * sqrt(max(0.0, 1.0 - f * f))
        )

    def flank(self, u: Float64, e: Float64, s: Float64 = 1.0) -> V3:
        var y = self.yc(u) + e * self.hd(u)
        return V3(s * self.surf_x(u, y), y, self.z(u))

    def lip_y(self, u: Float64) -> Float64:
        var t = clamp((u - self.u_f) / (self.u_c - self.u_f), 0.0, 1.0)
        return (
            self.y_f
            + (self.y_c - self.y_f) * pow(t, 0.7)
            - self.smile * 0.012 * self.tl * sin(pi * t)
        )

    def lip_point(
        self, t: Float64, s: Float64, inset: Float64, dy: Float64 = 0.0
    ) -> V3:
        var u = self.u_f + (self.u_c - self.u_f) * pow(t, 0.75)
        var y = self.lip_y(u) + dy
        return V3(s * self.surf_x(u, y) * inset, y, self.z(u))

    def pick_parent(self, u: Float64) -> String:
        var i = Int(floor((u - self.occ) / (self.pc - self.occ) * 12.0))
        return spine_name(max(0, min(11, i)))

    def bone_at(self, u: Float64) -> String:
        return String("head") if u < self.occ else self.pick_parent(u)


def _geo(t: Traits) -> _Geo:
    return _Geo(
        t.variant,
        t.get("girthK"),
        t.get("finK"),
        t.get("dorsalK"),
        t.get("pecK"),
        t.get("tailK"),
        t.get("lowLobeK"),
    )


def _pec_dir(abduct: Float64, droop: Float64) -> V3:
    var ab = abduct * D2R
    var dr = droop * D2R
    return normalize(V3(sin(ab) * cos(dr), -sin(dr), -cos(ab) * cos(dr)))


def _fin_chord(s: V3) -> V3:
    # The chord of a fin whose span runs along `s`: forward, square to it.
    var f = V3(0.0, 0.0, 1.0)
    return normalize(f - s * dot(f, s))


def shark_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one shark: procedural-animals' `variation`.

    The variant is the great white unless one is asked for. Females are
    larger. A young shark, drawn about one time in seven, is small, with
    a bigger head and fins. Within a variant the draw sets the girth, the
    fin and tail proportions, the dorsal tone, the scars and the nicks in
    the fins.

    Args:
        r: The individual's stream.
        options: The caller's sex, age, variant and quality.

    Returns:
        The traits.

    Raises:
        Error: If the requested variant is not one of the two.
    """
    var variant = WHITE
    if options.variant.value >= 0:
        if options.variant.value >= 2:
            raise Error("The species has no such color variant")
        variant = options.variant.value
    var sex = pick_sex(options.sex, r)
    var age = options.age
    if age == ANY_AGE:
        age = JUVENILE if r.next() < 0.15 else ADULT
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var white = variant == WHITE
    var size = ((0.84 if white else 0.92) if male else 1.0) * (
        1.0 + (0.09 if white else 0.08) * r.g()
    )
    if juv:
        size = 0.36 + 0.14 * r.next() if white else 0.42 + 0.12 * r.next()
    var g = _Geo(variant, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
    var head_k = (1.0 + 0.03 * r.g()) * (1.1 if juv else 1.0)
    var big_female = not male and not juv
    t.set(
        "girthK",
        (1.0 + 0.05 * r.g())
        * (0.9 if juv else 1.0)
        * (1.03 if big_female else 1.0),
    )
    t.set("finK", (1.0 + 0.05 * r.g()) * (1.08 if juv else 1.0))
    t.set("pecK", 1.0 + 0.05 * r.g())
    t.set("dorsalK", (1.0 + 0.07 * r.g()) * (1.05 if juv else 1.0))
    t.set("tailK", 1.0 + 0.04 * r.g())
    t.set("lowLobeK", 1.0 + 0.06 * r.g())
    t.warps.add(scale_about_warp(g.head_o, head_k, 0.1 * g.tl, 0.26 * g.tl))
    var tones: List[Float64] = [0.45, 0.35, 0.2] if white else [0.5, 0.3, 0.2]
    var x = r.next()
    var acc = 0.0
    var tone = 2
    for i in range(3):  # pragma: no branch
        acc += tones[i]
        if x < acc:
            tone = i
            break
    t.set("tone", Float64(tone))
    t.set("coatShade", 0.9 * r.g())
    t.set("bndShift", (0.1 if white else 0.06) * r.g())
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set(
        "scarK",
        (0.2 if juv else 1.0) * (0.9 if male else 1.3) * (0.4 + 0.9 * r.next()),
    )
    # Nicks in the trailing edges of the fins: old bites and abrasion.
    var nicks: Int
    if juv:
        nicks = 1 if r.next() < 0.15 else 0
    else:
        nicks = Int(floor(r.next() * (3.6 if white else 2.2)))
    t.set("nicks", Float64(nicks))
    for i in range(nicks):
        var key = "nick" + String(i)
        t.set(key + "caudal", 1.0 if r.next() < 0.2 else 0.0)
        t.set(key + "t", 0.1 + 0.8 * r.next())
        t.set(key + "r", (0.0035 if white else 0.004) + 0.004 * r.next())
    # The reference shark is TL = 1 / cellK long: `size` makes it real.
    t.set("size", size * g.real_tl * g.cell_k)
    t.set("minThick", CELL * 1.2)
    # The teeth are sub-pixel from the `MEDIUM` tier on: the original
    # leaves them out there.
    t.set("teeth", 1.0 if options.quality.resolution() < 1.9 else 0.0)
    return t^


def shark_eye(t: Traits) -> EyeSpec:
    """Return the shark's left eye: small and lidless in the white shark,
    with a lower lid in the blacktip.

    Args:
        t: The individual. The eye follows the variant's head.

    Returns:
        The eye, from the reference origin.
    """
    var g = _geo(t)
    var r = g.eye_r
    var bird = not g.white
    return EyeSpec(
        V3(g.eye_x, g.eye_y, g.eye_z),
        r,
        0.0,
        1.38,
        0.05,
        0.0,
        r * (1.1 if bird else 1.0),
        r * 0.42 if bird else 0.0,
        0.0,
        0.0,
        r * (0.42 if bird else 0.3),
        r * (0.84 if bird else 0.95),
    )


def shark_look(t: Traits) -> EyeLook:
    """Return the shark's eye colors: the white shark's black eye, or the
    blacktip's green-gray iris.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if t.variant == WHITE:
        return EyeLook(
            srgb(0x07080A),
            mix3(srgb(0x101820), srgb(0x1A2430), 0.35),
            srgb(0x040506),
            srgb(0xD6D6D0),
            0.77,
            0.0,
        )
    return EyeLook(
        srgb(0x1C1F18),
        mix3(srgb(0x6F7564), srgb(0x8F9480), 0.35),
        srgb(0x2A2D24),
        srgb(0x9A9A92),
        0.52,
        0.0,
    )


def shark_rig(t: Traits) raises -> Rig:
    """Return the shark's skeleton in bind pose: the swimmer bone set.

    The vertebral column climbs into the upper caudal lobe: the
    heterocercal tail.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var g = _geo(t)
    var tl = g.tl
    var n = 12
    var m = 3
    var rig = Rig()
    rig.set("snout", V3(0.0, g.yc(0.0) + g.snout_y * tl, g.z0))
    for i in range(n + 1):  # pragma: no branch
        var u = g.occ + (g.pc - g.occ) * Float64(i) / Float64(n)
        rig.set(spine_name(i), V3(0.0, g.yc(u), g.z(u)))
    var ua = g.c_ua
    var seg_l = (g.pc - g.occ) / Float64(n) * tl
    var last = rig.j(spine_name(n))
    last = V3(last.x, last.y + sin(0.17 * ua) * seg_l, last.z)
    rig.set(spine_name(n), last)
    rig.set("caudal0", last)
    var cl = g.c_up * 0.92 * tl
    var q = last
    var fac: List[Float64] = [0.54, 0.89, 1.2]
    for j in range(1, m + 1):  # pragma: no branch
        var a = fac[j - 1] * ua
        var l = cl / Float64(m)
        q = V3(0.0, q.y + sin(a) * l, q.z - cos(a) * l)
        rig.set("caudal" + String(j), q)
    rig.set(
        "jawHinge",
        V3(0.0, g.y_c - g.jaw_depth * 0.35 * tl, g.z(g.u_c + 0.012)),
    )
    rig.set("jawTip", V3(0.0, g.y_f - 0.004 * tl, g.z(g.u_f + 0.004)))
    rig.set("premaxBase", V3(0.0, g.y_c + 0.035 * tl, g.z(g.u_c + 0.01)))
    rig.set("premaxTip", V3(0.0, g.y_f + 0.012 * tl, g.z(g.u_f + 0.006)))
    var pb = _pec_base(g)
    rig.set("pecBaseL", pb)
    rig.set("pecUpL", pb + V3(0.0, 0.002 * tl, 0.03 * tl))
    rig.set(
        "pecTipL",
        pb
        + _pec_dir(g.p_abduct, g.p_droop) * (g.p_len * g.fin_k * g.pec_k * tl),
    )
    var pl = _pel_base(g)
    rig.set("pelBaseL", pl)
    rig.set("pelFrontL", pl + V3(0.002 * tl, 0.0, 0.02 * tl))
    rig.set("pelTipL", _pel_tip(g))
    rig.mirror_joints()
    swimmer_bones(
        rig,
        n,
        m,
        g.pick_parent(g.p_u),
        g.pick_parent(g.v_u),
        upper_jaw=True,
        opercula=False,
    )
    return rig^


def _pec_base(g: _Geo) -> V3:
    var pb = g.flank(g.p_u, g.p_e)
    return V3(pb.x - 0.004 * g.tl, pb.y, pb.z)


def _pel_base(g: _Geo) -> V3:
    var tl = g.tl
    return V3(g.hw(g.v_u) * 0.42, g.belly(g.v_u, 0.42) + 0.004 * tl, g.z(g.v_u))


def _pel_tip(g: _Geo) -> V3:
    var qd = normalize(V3(sin(g.v_abduct * D2R) * 0.9, -0.5, -1.0))
    return _pel_base(g) + qd * (g.v_len * g.fin_k * g.tl)


def _rz_at(u: Float64) -> Float64:
    var grow = 0.012 + 0.033 * clamp((u - 0.12) / 0.16, 0.0, 1.0)
    return min(0.045, min(u * 0.9 + 0.003, grow))


def _step_at(u: Float64) -> Float64:
    return max(0.003, min(0.0075, _rz_at(u) / 4.5))


def _station(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    g: _Geo,
    u: Float64,
    part: SurfacePart,
) raises:
    # Two ellipsoids a station: the teardrop section.
    var tl = g.tl
    var rz = _rz_at(u) * tl
    var hd = g.hd(u)
    var hw = g.hw(u)
    var yc = g.yc(u)
    _ = m.ell(
        tag,
        bone,
        V3(0.0, yc, g.z(u)),
        V3(hw * g.wk(u), hd, rz),
        k=0.006 * tl,
        part=part,
    )
    _ = m.ell(
        tag,
        bone,
        V3(0.0, yc - 0.3 * hd, g.z(u)),
        V3(hw, 0.7 * hd, rz),
        k=0.006 * tl,
        part=part,
    )


def _taper_fin(
    mut m: SdfModel,
    tag: String,
    bone: BoneId,
    origin: V3,
    u: V3,
    v: V3,
    poly: List[Float64],
    root_a: Float64,
    root_b: Float64,
    t_root: Float64,
    t_edge: Float64,
    k: Float64,
    along_a: Float64 = 0.0,
    along_b: Float64 = 0.0,
) raises:
    # A fleshy fin: a thin slab with the full outline, and six thicker
    # slabs of the outline shrunk toward the root, smoothly united: an
    # airfoil that thins toward its trailing edge.
    var stretch = along_a != 0.0 or along_b != 0.0
    var al = sqrt(along_a * along_a + along_b * along_b)
    var ex = along_a / al if stretch else 0.0
    var ey = along_b / al if stretch else 0.0
    for i in range(7):  # pragma: no branch
        var f = Float64(i) / 6.0
        var sc = 1.0 - 0.72 * f
        var th = t_edge + (t_root - t_edge) * pow(f, 1.2)
        var pts = List[Float64](capacity=len(poly))
        # The fin tables are literal outlines.
        for j in range(len(poly) // 2):
            var da = poly[j * 2] - root_a
            var db = poly[j * 2 + 1] - root_b
            if stretch:
                # Shrink across the root line more than along it.
                var along = da * ex + db * ey
                var across = -da * ey + db * ex
                var al2 = along * (sc + (1.0 - sc) * 0.55)
                var ac2 = across * sc
                pts.append(root_a + al2 * ex - ac2 * ey)
                pts.append(root_b + al2 * ey + ac2 * ex)
            else:
                pts.append(root_a + da * sc)
                pts.append(root_b + db * sc)
        _ = m.fin(
            tag,
            bone,
            origin,
            u,
            v,
            pts,
            th,
            round=th * 0.5,
            k=(k if i == 0 else th * 1.2),
            thin=i == 0,
        )


def _median_fin(
    g: _Geo, which: Int
) -> Tuple[V3, List[Float64], Float64, Float64]:
    # A median fin's origin, its outline in meters (back, up) with the
    # base following the body's outline, and its root point.
    var tl = g.tl
    var u0 = g.d1_u if which == 0 else (g.d2_u if which == 1 else g.anal_u)
    var src = g.d1_poly.copy() if which == 0 else (
        g.d2_poly.copy() if which == 1 else g.anal_poly.copy()
    )
    var kv = g.dorsal_k if which == 0 else 1.0
    var dorsal = which < 2
    var y0 = g.top(u0) - 0.004 * tl if dorsal else g.bot(u0) + 0.004 * tl
    var poly = List[Float64](capacity=len(src))
    # The root reads the outline's second and next-to-last points.
    if len(src) < 4:
        return (V3(0.0, y0, g.z(u0)), poly^, 0.0, 0.0)
    # Two points at least, checked above.
    for i in range(len(src) // 2):  # pragma: no branch
        var a = src[i * 2] * tl
        var b = src[i * 2 + 1] * tl * kv
        var uu = min(u0 + a / tl, g.pc)
        var yy = g.top(uu) - 0.004 * tl if dorsal else g.bot(uu) + 0.004 * tl
        poly.append(a)
        poly.append(b + (yy - y0))
    var n = len(poly) // 2
    var root_a = poly[2] + 0.25 * (poly[(n - 2) * 2] - poly[2])
    var root_b = poly[3]
    return (V3(0.0, y0, g.z(u0)), poly^, root_a, root_b)


def _caudal_poly(g: _Geo) -> List[Float64]:
    # The caudal fin in the median plane, (back, up) from the precaudal
    # pit: a lunate, heterocercal outline.
    var tl = g.tl
    var hdp = g.hd(g.pc) / tl
    var ua = g.c_ua
    var la = g.c_la
    var up = g.c_up
    var low = g.c_low
    var pts = List[Float64]()
    pts.append(-0.035 * tl)
    pts.append(hdp * 0.6 * tl)
    for i in range(8):  # pragma: no branch
        var f = Float64(i) / 7.0
        var l = up * f
        var bow = 0.012 * sin(pi * f) * (1.0 - f * 0.3)
        pts.append((cos(ua) * l - sin(ua) * bow) * tl)
        pts.append((hdp * 0.85 * (1.0 - f) + sin(ua) * l + cos(ua) * bow) * tl)
    var tip_u = V3(cos(ua) * up, sin(ua) * up, 0.0)
    var fork = V3(g.c_fork * g.tail_k + 0.02, -0.004, 0.0)
    var tip_l = V3(cos(la) * low, sin(la) * low, 0.0)
    _caudal_edge(pts, g, tip_u, fork, 9, 0.028 * g.tail_k, True)
    _caudal_edge(pts, g, fork, tip_l, 6, 0.018 * g.tail_k, False)
    for i in range(1, 6):  # pragma: no branch
        var f = 1.0 - Float64(i) / 5.0
        var l = low * f
        var bow = 0.01 * sin(pi * f)
        pts.append((cos(la) * l) * tl)
        pts.append((-hdp * 0.85 * (1.0 - f) + sin(la) * l - cos(la) * bow) * tl)
    pts.append(-0.035 * tl)
    pts.append(-hdp * 0.6 * tl)
    return pts^


def _caudal_edge(
    mut pts: List[Float64],
    g: _Geo,
    a: V3,
    b: V3,
    n: Int,
    sag: Float64,
    from_tip: Bool,
):
    # Its two callers ask for nine and six points.
    for i in range(1, n + 1):
        var f = Float64(i) / Float64(n)
        var x = a.x + (b.x - a.x) * f
        var y = a.y + (b.y - a.y) * f
        var s = sag * sin(pi * f)
        var notch = 0.0
        if from_tip and g.c_notch > 0.0:
            notch = -g.c_notch * exp(-pow((f - 0.14) / 0.06, 2.0))
        pts.append((x - s + notch) * g.tl)
        pts.append(y * g.tl)


def _scaled(poly: List[Float64], ka: Float64, ky: Float64) -> List[Float64]:
    var out = List[Float64](capacity=len(poly))
    # Its callers pass the literal fin outlines.
    for i in range(len(poly) // 2):
        out.append(poly[i * 2] * ka)
        out.append(poly[i * 2 + 1] * ky)
    return out^


def _lip_points(g: _Geo) -> List[Float64]:
    var out = List[Float64]()
    for i in range(9):  # pragma: no branch
        var u = g.u_f + (g.u_c - g.u_f) * Float64(i) / 8.0
        out.append(g.z(u))
        out.append(g.lip_y(u))
    return out^


def shark_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the shark: procedural-animals' `sculptShark`, primitive for
    primitive.

    The body is a chain of teardrop sections, the fins are tapered
    airfoils, the lower jaw is cut from the same sections by two
    complementary profile prisms, and the teeth are their own rigid
    parts. Males carry claspers.

    Args:
        m: The sculpt to add to.
        rig: The shark's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var g = _geo(t)
    var tl = g.tl
    var cell = CELL * tl * g.cell_k

    # BODY: two ellipsoids a station, closely spaced.
    var u = 0.004
    while u <= g.pc + 0.0001:
        var uu = min(u, g.pc)
        _station(
            m,
            "head" if uu < 0.24 else "body",
            rig.bone(g.bone_at(uu)),
            g,
            uu,
            BODY,
        )
        u += _step_at(u)
    # The peduncle runs on into the caudal fin base.
    _ = m.ell(
        "body",
        rig.bone("caudal0"),
        V3(0.0, g.yc(g.pc) + 0.004 * tl, g.z(g.pc + 0.02)),
        V3(g.hw(g.pc) * 0.75, g.hd(g.pc) * 0.95, 0.03 * tl),
        k=0.006 * tl,
    )
    # The caudal keel of the white shark: a ridge along the peduncle.
    if g.c_keel > 0.0:
        u = 0.69
        while u <= g.pc + 0.025:
            var f = sin(pi * min(1.0, (u - 0.69) / (g.pc + 0.03 - 0.69)))
            var uc = min(u, g.pc)
            _ = m.ell(
                "keel",
                rig.bone(g.bone_at(min(u, g.pc - 0.001))),
                V3(0.0, g.yc(uc), g.z(u)),
                V3(
                    min(g.hw(uc), g.hw(g.pc)) + g.c_keel * tl * f,
                    g.hd(uc) * 0.22,
                    0.02 * tl,
                ),
                k=0.008 * tl,
            )
            u += 0.012

    # HEAD: a slight swelling around the small eye, and the gum pads.
    var head = rig.bone("head")
    var er = g.eye_r
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere(
            "orbit",
            head,
            V3(s * (g.eye_x - 0.6 * er), g.eye_y, g.eye_z),
            er * 1.5,
            k=er * 1.2,
        )
    var upper = rig.bone("upperJaw")
    for s in [1.0, -1.0]:  # pragma: no branch
        for i in range(5):  # pragma: no branch
            var f = Float64(i) / 4.0
            _ = m.sphere(
                "gumU",
                upper,
                g.lip_point(f * 0.92, s, 0.6, 0.016 * tl),
                0.014 * tl * (1.0 - 0.3 * f),
                k=0.009 * tl,
            )

    # MEDIAN FINS: tapered airfoils in the x = 0 plane.
    var back = V3(0.0, 0.0, -1.0)
    var yax = V3(0.0, 1.0, 0.0)
    var bones: List[String] = [
        g.bone_at(g.d1_u + 0.04),
        g.bone_at(g.d2_u),
        g.bone_at(g.anal_u),
    ]
    var names: List[String] = ["dorsal1", "dorsal2", "anal"]
    var thick: List[Float64] = [g.d1_thick, 0.006, 0.006]
    for i in range(3):  # pragma: no branch
        var mf = _median_fin(g, i)
        _taper_fin(
            m,
            names[i],
            rig.bone(bones[i]),
            mf[0],
            back,
            yax,
            mf[1],
            mf[2],
            mf[3],
            thick[i] * tl,
            max(2.1 * cell, thick[i] * tl * 0.28),
            thick[i] * tl * 0.9,
        )
    _taper_fin(
        m,
        "caudal",
        rig.bone("caudal0"),
        g.pit,
        back,
        yax,
        _caudal_poly(g),
        0.01 * tl,
        0.02 * tl,
        g.c_thick * tl,
        max(2.1 * cell, g.c_thick * tl * 0.3),
        g.c_thick * tl,
        cos(g.c_ua),
        sin(g.c_ua),
    )

    # PAIRED FINS: stiff hydrofoils, and the claspers of males.
    for side in [String("L"), String("R")]:  # pragma: no branch
        var s = 1.0 if side == "L" else -1.0
        var b = rig.j("pecBase" + side)
        var pd = _pec_dir(g.p_abduct, g.p_droop)
        var sp = V3(pd.x * s, pd.y, pd.z)
        var ch = _fin_chord(sp)
        var span = g.p_len * g.fin_k * g.pec_k * tl
        var pec = rig.bone("pectoral" + side)
        _taper_fin(
            m,
            "pectoral",
            pec,
            b,
            sp,
            ch,
            _scaled(g.p_poly, span, tl * g.fin_k),
            0.02 * span,
            0.03 * tl,
            g.p_thick * tl,
            max(2.1 * cell, g.p_thick * tl * 0.2),
            g.p_thick * tl * 0.8,
            1.0,
            0.12,
        )
        # The fleshy base blends into the flank.
        _ = m.ell(
            "pecBase",
            pec,
            b + sp * (0.02 * tl),
            V3(0.035 * tl, 0.0085 * tl, 0.045 * tl),
            axis=ch,
            up=normalize(cross(sp, ch)),
            k=0.01 * tl,
        )
        var pb = rig.j("pelBase" + side)
        var vs = normalize(rig.j("pelTip" + side) - pb)
        var vch = _fin_chord(vs)
        var vspan = g.v_len * g.fin_k * tl
        var pel = rig.bone("pelvic" + side)
        _taper_fin(
            m,
            "pelvic",
            pel,
            pb,
            vs,
            vch,
            _scaled(g.v_poly, vspan, tl),
            0.05 * vspan,
            0.01 * tl,
            g.v_thick * tl,
            max(2.1 * cell, g.v_thick * tl * 0.3),
            g.v_thick * tl * 0.8,
        )
        if t.male():
            var cl = g.clasper * tl * (0.35 if t.juvenile() > 0.0 else 1.0)
            var a = pb + V3(-s * 0.01 * tl, -0.004 * tl, -0.012 * tl)
            var d = normalize(V3(s * 0.05, -0.18, -1.0))
            _ = m.cone(
                "clasper",
                pel,
                a,
                a + d * cl,
                0.0065 * tl,
                0.0035 * tl,
                k=0.004 * tl,
            )

    # CARVERS: the lower jaw's prism, the mouth, the eyes and nostrils.
    var y_low = g.bot(g.u_f) - 0.06 * tl
    var lip = _lip_points(g)
    var zh = g.z(g.u_c + 0.022)
    var zb = g.z(g.u_c + 0.06)
    var jd = g.jaw_depth * tl
    var zf = g.z(g.u_f)
    var zs = g.z0 + 0.03 * tl
    var jaw_poly: List[Float64] = [zf + 0.006 * tl, g.y_f - 0.02 * tl]
    # The lip has its points.
    for v in lip:  # pragma: no branch
        jaw_poly.append(v)
    var tail_pts: List[Float64] = [
        zh,
        g.y_c - jd * 0.5,
        zb,
        y_low,
        zf + 0.006 * tl,
        y_low,
    ]
    for v in tail_pts:  # pragma: no branch
        jaw_poly.append(v)
    var gap = 0.0012 * tl
    var wide = 0.6 * tl
    var o = V3(0.0, 0.0, 0.0)
    var zax = V3(0.0, 0.0, 1.0)
    _ = m.fin(
        "mouthcut",
        head,
        o,
        zax,
        yax,
        offset_poly(jaw_poly, gap * 0.5),
        wide,
        round=0.0,
        k=0.002 * tl,
        carve=True,
    )
    var cav_u = g.u_f + (g.u_c - g.u_f) * 0.55
    var cav_c = V3(0.0, g.lip_y(cav_u) + 0.004 * tl, g.z(cav_u))
    var cav_r = V3(g.hw(cav_u) * 0.68, 0.014 * tl, (g.u_c - g.u_f) * 0.62 * tl)
    _ = m.ell("mouth", head, cav_c, cav_r, k=0.003 * tl, carve=True)
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere(
            "eyesocket",
            head,
            V3(s * g.eye_x, g.eye_y, g.eye_z),
            er * 1.05,
            k=er * 0.25,
            carve=True,
        )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.ell(
            "nostril",
            head,
            g.flank(g.nostril_u, g.nostril_e, s),
            V3(0.002 * tl, 0.0018 * tl, 0.008 * tl),
            axis=normalize(V3(s * 0.5, 0.0, 1.0)),
            k=0.002 * tl,
            carve=True,
        )

    # NICKS: old bites carved out of the trailing edges.
    for i in range(Int(t.get("nicks", 0.0))):
        var key = "nick" + String(i)
        var nt = t.get(key + "t")
        var nr = t.get(key + "r")
        if t.get(key + "caudal") > 0.5:
            var l = g.c_up * (0.55 + 0.35 * nt)
            _ = m.sphere(
                "nick",
                rig.bone("caudal2"),
                V3(
                    0.0,
                    g.pit.y + sin(g.c_ua) * l * tl,
                    g.pit.z - cos(g.c_ua) * l * tl - 0.012 * tl,
                ),
                nr * tl,
                k=0.0015 * tl,
                carve=True,
            )
        else:
            var i0 = 5
            var i1 = len(g.d1_poly) // 2 - 2
            var f = Float64(i1 - i0) * nt
            var j = min(i1 - 1, i0 + Int(floor(f)))
            var fr = f - floor(f)
            var pa = g.d1_poly[j * 2]
            var pb = g.d1_poly[j * 2 + 1]
            var a = pa + (g.d1_poly[j * 2 + 2] - pa) * fr
            var b = (pb + (g.d1_poly[j * 2 + 3] - pb) * fr) * g.dorsal_k
            var uu = g.d1_u + a
            var y = g.top(min(uu, g.pc)) - 0.004 * tl + b * tl
            _ = m.sphere(
                "nick",
                rig.bone(g.bone_at(g.d1_u + 0.04)),
                V3(0.0, y, g.z(uu) - nr * 0.35 * tl),
                nr * tl,
                k=0.0015 * tl,
                carve=True,
            )

    # LOWER JAW: its own surface, the complement of the jaw prism.
    var jaw = rig.bone("jaw")
    u = 0.004
    while u <= g.u_c + 0.075:
        _station(m, "jaw", jaw, g, u, JAW)
        u += _step_at(u)
    var big = tl
    var rest: List[Float64] = [
        zf + 0.006 * tl,
        g.y_f - 0.02 * tl,
        zs,
        g.y_f - 0.02 * tl,
        zs,
        g.y_f + big,
        zb - big,
        g.y_f + big,
        zb - big,
        y_low,
        zb,
        y_low,
        zh,
        g.y_c - jd * 0.5,
    ]
    # The lip has its points.
    for i in range(len(lip) // 2 - 1, -1, -1):  # pragma: no branch
        rest.append(lip[i * 2])
        rest.append(lip[i * 2 + 1])
    _ = m.fin(
        "jawcut",
        jaw,
        o,
        zax,
        yax,
        offset_poly(rest, gap * 0.5),
        wide,
        round=0.0,
        k=0.002 * tl,
        carve=True,
        part=JAW,
    )
    _ = m.ell("mouth", jaw, cav_c, cav_r, k=0.003 * tl, carve=True, part=JAW)

    # TEETH: rows of serrated triangles, rigid on each jaw.
    if t.get("teeth", 1.0) > 0.5:
        _teeth(m, rig, g, t)


def _teeth(mut m: SdfModel, rig: Rig, g: _Geo, t: Traits) raises:
    var tl = g.tl
    var white = g.white
    var n = 12 if white else 13
    var h0 = (
        (0.0105 if white else 0.0075)
        * tl
        * (0.8 if t.juvenile() > 0.0 else 1.0)
    )
    for row in range(2):  # pragma: no branch
        var upper = row == 0
        var bone = rig.bone("upperJaw") if upper else rig.bone("jaw")
        var dir = -1.0 if upper else 1.0
        var inset = 0.86 if upper else 0.8
        for s in [1.0, -1.0]:  # pragma: no branch
            for i in range(n):  # pragma: no branch
                var f = (Float64(i) + 0.5) / Float64(n)
                var p = g.lip_point(
                    f * 0.94, s, inset, 0.003 * tl if upper else -0.004 * tl
                )
                var pn = g.lip_point(min(1.0, f * 0.94 + 0.02), s, inset)
                var tang = normalize(pn - p)
                var h = h0 * (1.0 - 0.55 * f * f) * (1.0 if upper else 0.9)
                var wk = (0.85 if upper else 0.6) if white else (
                    0.55 if upper else 0.45
                )
                var w = h * wk
                var lean = -0.12 - 0.25 * f * (1.0 if upper else -0.3)
                var axis = normalize(V3(0.0, dir, lean))
                var v = normalize(axis + V3(-s, 0.0, 0.0) * 0.2)
                var tu = normalize(tang - v * dot(tang, v))
                var base = p - v * (h * 0.35)
                var poly: List[Float64] = [
                    -w * 0.5,
                    0.0,
                    -w * 0.42,
                    h * 0.35,
                    -w * 0.12,
                    h * 0.85,
                    0.02 * w,
                    h,
                    w * 0.16,
                    h * 0.84,
                    w * 0.44,
                    h * 0.35,
                    w * 0.5,
                    0.0,
                ]
                var th = max(w * 0.34, 0.0022 * tl)
                _ = m.fin(
                    "tooth",
                    bone,
                    base,
                    tu,
                    v,
                    poly,
                    th,
                    round=th * 0.45,
                    k=0.0006 * tl,
                    part=TEETH,
                )


def _swatches() -> List[String]:
    return [
        String("flank"),
        "belly",
        "boundary",
        "finTip",
        "finUnder",
        "gum",
        "mouth",
        "tooth",
        "gill",
        "scar",
        "freckle",
        "paleBand",
        "flankBand",
    ]


def _colors(variant: Int) -> List[Int]:
    if variant == BLACKTIP:
        return [
            0x9D9B95,
            0xF1F0EC,
            0xC6C5C0,
            0x111112,
            0xE4E3DE,
            0xA88078,
            0x4A3434,
            0xF1ECE0,
            0x3A3634,
            0xB4B3AE,
            0x6A6964,
            0xD2D0CA,
            0x6E6D68,
        ]
    return [
        0x8E9497,
        0xF0EFEA,
        0xA9AEB0,
        0x19191B,
        0xDEDCD6,
        0xA87A7A,
        0x4A3436,
        0xF1ECE0,
        0x2A2224,
        0xB8BCBC,
        0x3C4248,
        0xB0B4B6,
        0x6E7478,
    ]


def shark_palette(t: Traits) raises -> Palette:
    """Return one shark's palette: its variant's colors and its own
    dorsal tone, a little lighter or darker.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: If the palette tables differ in length.
    """
    var pal = palette_of(_swatches(), _colors(t.variant))
    var tones: List[Int] = [
        0x757B7F,
        0x7E7A70,
        0x676E74,
    ] if t.variant == WHITE else [
        0x817E77,
        0x857F75,
        0x7B7C7A,
    ]
    var shade = t.get("coatShade", 0.0)
    var back = srgb(tones[min(2, Int(t.get("tone", 0.0)))]) * (
        1.0 + 0.14 * shade
    )
    pal.set("back", back)
    pal.set("flank", mix3(pal.get("flank"), back, 0.35) * (1.0 + 0.1 * shade))
    return pal^


def _lerp_table(tbl: List[Float64], u: Float64) -> Float64:
    var n = len(tbl) // 2
    if u <= tbl[0]:
        return tbl[1]
    for i in range(1, n):
        if u <= tbl[i * 2]:
            var t = (u - tbl[i * 2 - 2]) / (tbl[i * 2] - tbl[i * 2 - 2])
            var s = t * t * (3.0 - 2.0 * t)
            return tbl[i * 2 - 1] + (tbl[i * 2 + 1] - tbl[i * 2 - 1]) * s
    return tbl[n * 2 - 1]


def _e_bound(white: Bool, u: Float64) -> Float64:
    # The height of the pale belly's boundary along the body, as a
    # fraction of the half depth.
    if white:
        var tbl: List[Float64] = [
            0, -0.9, 0.03, -0.55, 0.06, -0.32, 0.12, -0.3, 0.2, -0.26,
            0.28, -0.3, 0.36, -0.14, 0.46, -0.08, 0.56, 0.0, 0.66, 0.02,
            0.74, 0.1, 0.8, 0.14,
        ]  # fmt: skip
        return _lerp_table(tbl, u)
    var tbl: List[Float64] = [
        0, -0.5, 0.08, -0.42, 0.18, -0.4, 0.3, -0.42, 0.45, -0.38, 0.6,
        -0.3, 0.72, -0.2, 0.8, -0.1,
    ]  # fmt: skip
    return _lerp_table(tbl, u)


def _seg_dist(
    px: Float64,
    py: Float64,
    ax: Float64,
    ay: Float64,
    bx: Float64,
    by: Float64,
) -> Tuple[Float64, Float64]:
    # The distance from a point to a segment, and where along it.
    var ex = bx - ax
    var ey = by - ay
    var l2 = ex * ex + ey * ey
    var t = clamp(((px - ax) * ex + (py - ay) * ey) / max(l2, 1e-18), 0.0, 1.0)
    var dx = px - ax - ex * t
    var dy = py - ay - ey * t
    return (sqrt(dx * dx + dy * dy), t)


def _line_dist(
    px: Float64, py: Float64, pts: List[Float64], w: List[Float64]
) -> Float64:
    # The distance from a point to a polyline of varying half width,
    # below zero inside it.
    var best = 1e9
    # Its callers pass literal polylines.
    for i in range(len(pts) // 2 - 1):
        var r = _seg_dist(
            px, py, pts[i * 2], pts[i * 2 + 1], pts[i * 2 + 2], pts[i * 2 + 3]
        )
        best = min(best, r[0] - (w[i] + (w[i + 1] - w[i]) * r[1]))
    return best


def _trail_dist(poly: List[Float64], a: Float64, b: Float64) -> Float64:
    # The distance from (a, b) to the caudal fin's trailing edge: the
    # outline between the upper and the lower tip.
    var n = len(poly) // 2
    var iu = 0
    var il = 0
    # The caudal outline is a literal table.
    for i in range(n):
        if poly[i * 2 + 1] > poly[iu * 2 + 1]:
            iu = i
        if poly[i * 2 + 1] < poly[il * 2 + 1]:
            il = i
    var best = 1e9
    # The caudal outline lists its upper tip before its lower.
    for i in range(iu, il):
        var r = _seg_dist(
            a, b, poly[i * 2], poly[i * 2 + 1], poly[i * 2 + 2], poly[i * 2 + 3]
        )
        best = min(best, r[0])
    return best


def _scars(g: _Geo, t: Traits) -> List[Float64]:
    # The seeded scars, as polylines on the flank in (u, e): side, then
    # five points, five half widths and a strength, for each.
    var tl = g.tl
    var white = g.white
    var r = AnimalRandom(7331 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var scar_k = t.get("scarK", 1.0)
    var count: Int
    if white:
        count = Int(floor(scar_k * (1.5 + 3.5 * r.next()) + 0.5))
    else:
        count = 1 if r.next() < 0.35 * scar_k else 0
    var out = List[Float64]()
    for _ in range(count):
        var s = 1.0 if r.next() < 0.5 else -1.0
        var u0 = 0.1 + 0.55 * r.next()
        var e0 = 0.05 + 0.7 * r.next()
        var ang = (r.next() - 0.5) * 1.4
        var w = (0.0011 + 0.0007 * r.next()) * tl
        var k = 0.22 + 0.18 * r.next()
        var hd0 = max(0.01 * tl, g.hd(u0))
        var rake = False
        if white:
            rake = r.next() < 0.3
        if rake:
            # A healed tooth rake: short parallel scratches.
            var n = 3 + Int(floor(r.next() * 3.0))
            var l = (0.008 + 0.006 * r.next()) * tl
            var gap = 0.006 * tl
            # A rake has three scratches or more.
            for j in range(n):  # pragma: no branch
                var off = Float64(j) - Float64(n) / 2.0
                _scratch(
                    out,
                    g,
                    u0 + off * gap * cos(ang) / tl,
                    e0 + off * gap * sin(ang) / hd0,
                    s,
                    ang + pi / 2.0,
                    l * (0.8 + 0.4 * r.next()),
                    w * 0.9,
                    k,
                )
        else:
            _scratch(
                out, g, u0, e0, s, ang, (0.012 + 0.03 * r.next()) * tl, w, k
            )
    return out^


def _scratch(
    mut out: List[Float64],
    g: _Geo,
    u0: Float64,
    e0: Float64,
    s: Float64,
    ang: Float64,
    l: Float64,
    w: Float64,
    k: Float64,
):
    var tl = g.tl
    var hd0 = max(0.01 * tl, g.hd(u0))
    out.append(s)
    for j in range(5):  # pragma: no branch
        var f = Float64(j) / 4.0
        var du = cos(ang) * (f - 0.5) * l / tl
        var de = sin(ang) * (f - 0.5) * l / hd0
        out.append(clamp(u0 + du, 0.03, g.pc))
        out.append(clamp(e0 + de, -0.6, 0.95))
    for j in range(5):  # pragma: no branch
        out.append(w * (0.35 if j == 0 or j == 4 else 1.0))
    out.append(k)


def _is_fin(tag: String) -> Bool:
    return (
        tag == "dorsal1"
        or tag == "dorsal2"
        or tag == "anal"
        or tag == "caudal"
        or tag == "pectoral"
        or tag == "pelvic"
        or tag == "clasper"
    )


def shark_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a shark.

    The skin is matte denticles, gray above a pale belly whose boundary
    is crisp and ragged. The white shark has pale pectoral undersides
    with black tips, freckles along the lip and pale scars. The blacktip
    has black tips on every fin, a pale band under the dorsal tip, a
    dusky flank band and a white flank wedge. Gill slits, nostrils and
    pores are dark marks.

    Args:
        pal: The individual's palette.
        t: The individual.
        tag: The tag of the solid the vertex lies on.
        bone: The bone that solid rides.
        s: The vertex.

    Returns:
        The paint.
    """
    if s.part == TEETH:
        return Paint(pal.get("tooth"), KERATIN)
    var g = _geo(t)
    var tl = g.tl
    var white = g.white
    var p = s.p
    var n = s.n
    var seed = Int(t.get("coatSeed", 0.0))
    var ox = Float64(seed % 997) * 0.731
    var oy = Float64(seed % 991) * 0.377
    var u = clamp(g.u(p.z), 0.0, 1.3)
    var uc = min(u, g.pc)
    var hdm = max(g.hd(uc), 0.03 * tl)
    var e = (p.y - g.yc(uc)) / hdm
    var back = pal.get("back")
    var flank = pal.get("flank")
    # The eye socket: a dark cup round the black eye.
    var eye_d = length(V3(abs(p.x) - g.eye_x, p.y - g.eye_y, p.z - g.eye_z))
    if eye_d < g.eye_r * 1.12:
        return Paint(V3(0.012, 0.011, 0.011), SKIN)
    # The lip line: a dark, neutral crease from the front of the gape to
    # its corner.
    var on_lip = u > g.u_f - 0.006 and u < g.u_c + 0.004
    if on_lip:
        var lip = abs(p.y - g.lip_y(clamp(u, g.u_f, g.u_c)))
        if lip < 0.0022 * tl:
            return Paint(mix3(back * 0.22, pal.get("mouth"), 0.25), SKIN)
    var m1 = (
        fbm3(V3(p.x * 6.0 / tl + ox, p.y * 6.0 / tl, p.z * 6.0 / tl + oy), 3)
        - 0.5
    )
    var m2 = (
        fbm3(
            V3(
                p.x * 22.0 / tl + oy,
                p.y * 22.0 / tl + 4.1,
                p.z * 22.0 / tl + ox,
            ),
            3,
        )
        - 0.5
    )
    var m3 = (
        fbm3(
            V3(
                p.x * 90.0 / tl + 7.7,
                p.y * 90.0 / tl + ox,
                p.z * 90.0 / tl + oy,
            ),
            2,
        )
        - 0.5
    )
    var up = smoothstep(-0.6, 1.0, e * 0.8 + n.y * 0.45)
    var c = mix3(flank, back, up)
    # The pale belly below a crisp, ragged boundary: domain-warped noise
    # at three scales.
    var wq = (
        (
            fbm3(
                V3(
                    p.x * 9.0 / tl + ox,
                    p.y * 9.0 / tl + 2.3,
                    p.z * 9.0 / tl + oy,
                ),
                2,
            )
            - 0.5
        )
        * 0.06
        * tl
    )
    var q = V3(p.x + wq, p.y - wq, p.z + wq * 1.7)
    var rag_k = 1.0 + 0.8 * smoothstep(0.55, 0.78, uc)
    var rag_a = 0.12 if white else 0.03
    var rag = rag_k * (
        rag_a
        * (
            fbm3(
                V3(
                    q.x * 14.0 / tl + 3.1 + ox,
                    q.y * 14.0 / tl + oy,
                    q.z * 14.0 / tl,
                ),
                3,
            )
            - 0.5
        )
        * 2.0
        + rag_a
        * 0.8
        * (
            fbm3(
                V3(
                    q.x * 38.0 / tl + oy,
                    q.y * 38.0 / tl + 1.7,
                    q.z * 38.0 / tl + ox,
                ),
                3,
            )
            - 0.5
        )
        + rag_a
        * 0.45
        * (
            fbm3(
                V3(
                    q.x * 95.0 / tl + 5.3,
                    q.y * 95.0 / tl + ox,
                    q.z * 95.0 / tl + oy,
                ),
                2,
            )
            - 0.5
        )
    )
    var b_shift = t.get("bndShift", 0.0)
    var belly = (
        (e - (_e_bound(white, uc) + rag + b_shift * smoothstep(0.08, 0.2, uc)))
        * hdm
        * 0.6
    )
    var mark = 1.0
    # The fleshy base of a pectoral fin wears the fin's colors.
    var ftag = String("pectoral") if tag == "pecBase" else tag
    var fin = _is_fin(ftag)
    if fin:
        var fin_paint = _fin_color(pal, t, g, ftag, bone, p, n, c)
        var w_fin = fin_paint[3]
        var belly_fin = fin_paint[2]
        mark = fin_paint[1]
        c = mix3(c, fin_paint[0], w_fin)
        belly = belly + (belly_fin - belly) * w_fin
        fin = w_fin > 0.5
    if not fin:
        # A thin shadow round the eye: the black eye stands out of the gray.
        c = mix3(
            c,
            back * 0.6,
            (1.0 - smoothstep(g.eye_r * 1.05, g.eye_r * 1.6, eye_d)) * 0.45,
        )
        if not white:
            # The white flank wedge: a pale tongue forward from above the
            # pelvic fins.
            var tw = clamp((u - 0.36) / 0.3, 0.0, 1.0)
            var ec = -0.05 - 0.2 * tw
            var hw = 0.03 + 0.22 * tw * tw
            var dw = (
                (abs(e - ec + rag * 0.3) - hw) * g.hd(uc) * 0.6
                + ((0.36 - u) * tl * 0.6 if u < 0.36 else 0.0)
                + ((u - 0.68) * tl if u > 0.68 else 0.0)
            )
            belly = min(belly, dw)
        # The ampullae: dark pores under and beside the snout.
        var pores = u > 0.006 and u < 0.085 and e < 0.35
        if pores:
            var cs = 0.008 * tl
            var cl = cells3(p * (1.0 / cs), seed % 7919)
            var dp = cl.nearest * cs - (0.0011 if white else 0.0012) * tl
            c = mix3(
                c,
                c * 0.6,
                (1.0 - smoothstep(-0.0012 * tl, 0.0025 * tl, dp)) * 0.45,
            )
        if white:
            # A few small dark dots along the upper lip, faint flecks on
            # the back.
            var m4 = (
                fbm3(
                    V3(
                        p.x * 160.0 / tl + oy,
                        p.y * 160.0 / tl + 2.9,
                        p.z * 160.0 / tl + ox,
                    ),
                    2,
                )
                - 0.5
            )
            var lipz = (
                (1.0 - smoothstep(0.07, 0.1, u))
                * smoothstep(0.03, 0.05, u)
                * (1.0 - smoothstep(0.08, 0.22, abs(e - (g.e_c + 0.12))))
            )
            var fk = smoothstep(0.3, 0.34, m4) * lipz * 0.7 + smoothstep(
                0.34, 0.37, m3
            ) * 0.12 * smoothstep(0.0, 0.5, e)
            c = mix3(c, pal.get("freckle"), clamp(fk, 0.0, 1.0) * 0.5)
        else:
            # The dusky band along the flank above the white wedge.
            var tb = clamp((u - 0.3) / 0.38, 0.0, 1.0)
            var db = abs(e - (-0.02 - 0.12 * tb + rag * 0.3)) / (
                0.07 + 0.05 * sin(pi * tb)
            )
            c = mix3(
                c,
                pal.get("flankBand"),
                (1.0 - smoothstep(0.6, 1.4, db))
                * smoothstep(0.26, 0.4, u)
                * (1.0 - smoothstep(0.66, 0.76, u))
                * 0.55,
            )
        mark = min(mark, _head_marks(g, p, u))
    # Scars: pale, slightly glossy scratches.
    var scars = _scars(g, t)
    var i = 0
    var ue = (p.y - g.yc(uc)) / max(1e-6, g.hd(uc))
    var side = 1.0 if p.x >= 0.0 else -1.0
    var hd_here = max(0.01 * tl, g.hd(uc))
    while i < len(scars):
        var near_side = scars[i] == side or abs(p.x) <= 0.02 * tl
        if near_side:
            var pts = List[Float64]()
            var ws = List[Float64]()
            for j in range(5):  # pragma: no branch
                pts.append(scars[i + 1 + j * 2] * tl)
                pts.append(scars[i + 2 + j * 2] * hd_here)
                ws.append(scars[i + 11 + j])
            var d = _line_dist(u * tl, ue * hd_here, pts, ws)
            c = mix3(
                c,
                pal.get("scar"),
                (1.0 - smoothstep(-0.0004 * tl, 0.0009 * tl, d))
                * scars[i + 16],
            )
        i += 17
    # Mottling on the gray, a little on the fins; the pale belly stays
    # clean.
    var dors = 0.5 + 0.5 * smoothstep(-0.4, 0.6, e)
    c = c * (1.0 + dors * (0.2 * m1 + 0.1 * m2 + (0.1 if white else 0.07) * m3))
    if s.part == JAW:
        belly = min(belly, -0.004 * tl + (e + 0.2) * 0.001)
    var bc = mix3(
        pal.get("belly"),
        pal.get("boundary"),
        smoothstep(-0.03 * tl, 0.0, belly) * 0.35,
    )
    c = mix3(c, bc, smoothstep(0.0012 * tl, -0.0012 * tl, belly))
    c = mix3(
        c,
        V3(0.006, 0.006, 0.007),
        smoothstep(0.0006 * tl, -0.0006 * tl, mark),
    )
    return Paint(c, SCALES)


def _head_marks(g: _Geo, p: V3, u: Float64) -> Float64:
    # The nostrils and the gill slits: dark lines laid out on the flank,
    # as a signed distance in meters.
    var tl = g.tl
    var mark = 1.0
    var s = 1.0 if p.x >= 0.0 else -1.0
    var near_nostril = u < g.nostril_u + 0.02
    if near_nostril:
        # An oblique slit under the snout.
        var c0 = g.flank(g.nostril_u, g.nostril_e, s)
        var ax = normalize(V3(s * 0.5, 0.0, 1.0))
        var w = max(0.0007 * tl, 0.3 * CELL * tl * g.cell_k)
        var d = p - c0
        var along = clamp(dot(d, ax), -0.0075 * tl, 0.0075 * tl)
        # The line lies on the outline, under the skin's blend: measure
        # across the skin.
        var skin = 0.0033 * tl
        var off = length(d - ax * along)
        var across = sqrt(max(0.0, off * off - skin * skin))
        var taper = 1.0 - 0.7 * pow(abs(along) / (0.0075 * tl), 2.0)
        mark = min(mark, across - w * taper)
    var near_gills = u > g.gill_u0 - 0.03 and u < g.gill_u1 + 0.03
    if near_gills:
        var uc = min(u, g.pc)
        var hd = max(1e-6, g.hd(uc))
        var e = (p.y - g.yc(uc)) / hd
        var w = max(
            (0.0013 if g.white else 0.0009) * tl,
            (0.45 if g.white else 0.35) * CELL * tl * g.cell_k * 1.3,
        )
        for i in range(5):  # pragma: no branch
            var ui = g.gill_u0 + (g.gill_u1 - g.gill_u0) * Float64(i) / 4.0
            var ln = 1.0 - 0.18 * abs(Float64(i) - 4.0 * 0.6) / 5.0
            var pts = List[Float64]()
            var ws = List[Float64]()
            for j in range(7):  # pragma: no branch
                var ej = (
                    g.gill_e0 + (g.gill_e1 - g.gill_e0) * ln * Float64(j) / 6.0
                )
                pts.append((ui - g.gill_lean * (ej - g.gill_e0)) * tl)
                pts.append(ej * hd)
                ws.append(w * (0.45 if j == 0 or j == 6 else 1.0))
            mark = min(mark, _line_dist(u * tl, e * hd, pts, ws))
    return mark


def _fin_color(
    pal: Palette,
    t: Traits,
    g: _Geo,
    tag: String,
    bone: String,
    p: V3,
    n: V3,
    body: V3,
) -> Tuple[V3, Float64, Float64, Float64]:
    # A fin's color, its mark, its belly pattern and its share against
    # the body's colors, from where the vertex lies in the fin's plane.
    var tl = g.tl
    var white = g.white
    var back = pal.get("back")
    var flank = pal.get("flank")
    var c: V3
    var mark = 1.0
    var belly_fin = 0.01 * tl
    var w_fin = 1.0
    if tag == "clasper":
        return (mix3(pal.get("finUnder"), flank, 0.5), mark, belly_fin, w_fin)
    var paired = tag == "pectoral" or tag == "pelvic"
    var origin: V3
    var fu: V3
    var fv: V3
    var poly: List[Float64]
    if paired:
        var s = 1.0 if bone.endswith("L") else -1.0
        if tag == "pectoral":
            var pb = _pec_base(g)
            origin = V3(pb.x * s, pb.y, pb.z)
            var pd = _pec_dir(g.p_abduct, g.p_droop)
            fu = V3(pd.x * s, pd.y, pd.z)
            poly = _scaled(
                g.p_poly, g.p_len * g.fin_k * g.pec_k * tl, tl * g.fin_k
            )
        else:
            var pb = _pel_base(g)
            var tip = _pel_tip(g)
            origin = V3(pb.x * s, pb.y, pb.z)
            fu = normalize(V3((tip.x - pb.x) * s, tip.y - pb.y, tip.z - pb.z))
            poly = _scaled(g.v_poly, g.v_len * g.fin_k * tl, tl)
        fv = fin_plane_v(fu, _fin_chord(fu))
    else:
        fu = V3(0.0, 0.0, -1.0)
        fv = V3(0.0, 1.0, 0.0)
        if tag == "caudal":
            origin = g.pit
            poly = _caudal_poly(g)
        else:
            var which = 0 if tag == "dorsal1" else (
                1 if tag == "dorsal2" else 2
            )
            var mf = _median_fin(g, which)
            origin = mf[0]
            poly = mf[1].copy()
            # The fin's colors blend into the body's over a short fillet.
            var uu = clamp(g.u(p.z), 0.0, g.pc)
            var dist = p.y - g.top(uu) if which < 2 else g.bot(uu) - p.y
            w_fin = smoothstep(-0.25, 1.0, dist / (0.012 * tl))
    var d = p - origin
    var a = dot(d, fu)
    var b = dot(d, fv)
    var max_a = 0.0
    var max_b = -1e9
    var min_b = 1e9
    # Its callers pass the literal fin outlines.
    for i in range(len(poly) // 2):
        max_a = max(max_a, poly[i * 2])
        max_b = max(max_b, poly[i * 2 + 1])
        min_b = min(min_b, poly[i * 2 + 1])
    if paired:
        # Pale undersides, read against the fin's own plane; the rim
        # stays gray.
        var nf = normalize(cross(fu, fv))
        var nd = dot(n, nf) * (1.0 if nf.y >= 0.0 else -1.0)
        var wu = smoothstep(-0.6, -0.85, nd)
        c = mix3(
            mix3(back, flank, 0.15),
            mix3(body, pal.get("finUnder"), 0.9 if white else 0.8),
            wu,
        )
        belly_fin = clamp((nd + 0.74) * 0.03 * tl, -0.01 * tl, 0.01 * tl)
        var span = max_a
        if white and tag == "pectoral":
            # A black blotch at the ventral tip, a dusky trailing margin.
            mark = min(
                mark, max((0.86 * span - a) * 0.5, (nd + 0.74) * 0.03 * tl)
            )
            c = mix3(c, back, smoothstep(0.55, 0.95, a / span) * 0.35 * wu)
        if not white:
            mark = min(
                mark, ((0.72 if tag == "pelvic" else 0.8) * span - a) * 0.6
            )
    elif tag == "dorsal1":
        c = mix3(back, flank, 0.1)
        if not white:
            mark = min(mark, (0.78 * max_b - b) * 0.6)
            # The pale band under the black tip.
            c = mix3(
                c,
                pal.get("paleBand"),
                (1.0 - smoothstep(0.08, 0.2, abs(b / max_b - 0.68))) * 0.55,
            )
    elif tag == "dorsal2" or tag == "anal":
        c = mix3(back, flank, 0.6 if tag == "anal" else 0.1)
        if not white:
            mark = min(
                mark,
                (b - 0.5 * min_b) * 0.6 if tag
                == "anal" else (0.55 * max_b - b) * 0.6,
            )
    else:
        c = mix3(back, flank, smoothstep(0.1, -0.15, b / tl) * 0.4)
        if not white:
            # A black lower lobe tip and a dusky trailing margin.
            var lx = cos(g.c_la) * g.c_low * tl
            var ly = sin(g.c_la) * g.c_low * tl
            var dl = sqrt((a - lx) ** 2 + (b - ly) ** 2) - 0.42 * g.c_low * tl
            var ux = cos(g.c_ua) * g.c_up * tl
            var uy = sin(g.c_ua) * g.c_up * tl
            var du = sqrt((a - ux) ** 2 + (b - uy) ** 2) - 0.12 * g.c_up * tl
            mark = min(mark, min(dl * 0.8, du * 0.8))
            mark = min(mark, _trail_dist(poly, a, b) - 0.006 * tl)
        else:
            c = mix3(c, back * 0.8, 0.3)
    return (c, mark, belly_fin, w_fin)
