# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The domestic pig, Sus scrofa domesticus: procedural-animals'
`species/pig/`.

A long fat barrel on short legs sunk into it, the wedge head ending in
the flat rostral disc on its own bone, small deep-set eyes, erect, semi
or lop ear leaves, and the corkscrew tail. Bare skin under sparse
bristles. The reference individual is a Large White finisher, 0.72 m at
the withers. The breeds are Large White, Landrace, Duroc, Hampshire,
Berkshire and spotted.
"""

from extensions.animals.coat import (
    KERATIN,
    SKIN,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    srgb,
)
from extensions.sdf.ids import BoneId
from extensions.animals.parts import (
    EAR,
    JAW,
    TAIL,
    TEETH,
)
from extensions.sdf.sculpt import ell_y
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    draw_u32,
    is_front_limb,
    imul32,
    is_limb,
    stream_of,
    lid_distance,
)
from extensions.animals.noise import fbm3, vnoise3
from extensions.animals.options import (
    FEMALE,
    JUVENILE,
    MALE,
    ADULT,
    AnimalOptions,
    AnimalRandom,
)
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.species.hoofed import (
    HeadFrame,
    head_frame,
    hoofed_bones,
)
from extensions.animals.traits import Traits
from extensions.sdf.vector import (
    V3,
    clamp,
    cross,
    dot,
    length,
    lerp,
    normalize,
    smoothstep,
    rotate_about,
)
from extensions.animals.warp import (
    girth_warp,
    legs_warp,
    length_warp,
    scale_about_warp,
)
from std.math import asin, atan2, cos, exp, floor, pi, pow, sin, sqrt
from extensions.sdf.distance import segment_distance

comptime TAIL_SEGS = 10
# The head's origin: on the head's axis level with the eyes. The head is
# carried 35 degrees nose-down.
comptime HEAD_O = V3(0.0, 0.585, 0.59)
comptime HEAD_PITCH = 35.0
# The snout's length factor at a `snoutLen` of one.
comptime SNOUT_K = 1.15
# The finest cell, at the `HERO` tier: the feet's cell in the original,
# between its head (4.1 mm) and its ears and jaw (3 mm).
comptime CELL = 0.0035
comptime EAR_BASE = V3(0.07, 0.056, -0.074)

# The breeds, in procedural-animals' order.
comptime LARGEWHITE = 0
comptime LANDRACE = 1
comptime DUROC = 2
comptime HAMPSHIRE = 3
comptime BERKSHIRE = 4
comptime SPOTTED = 5

# Ear forms.
comptime ERECT = 0
comptime SEMI = 1
comptime LOP = 2


def pig_variant_names() -> List[String]:
    """Return the pig's breeds.

    Returns:
        Large White, Landrace, Duroc, Hampshire, Berkshire and spotted.
    """
    return [
        String("largewhite"),
        "landrace",
        "duroc",
        "hampshire",
        "berkshire",
        "spotted",
    ]


def _frame() -> HeadFrame:
    return head_frame(HEAD_O, HEAD_PITCH)


def _hl(v: V3) -> V3:
    return _frame().at_chained(v)


def _ear_type(variant: Int) -> Int:
    var lop = variant == LANDRACE or variant == SPOTTED
    if lop:
        return LOP
    if variant == DUROC:
        return SEMI
    return ERECT


def pig_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one pig: procedural-animals' `variation`.

    The stream is re-mixed with the seed, as the original does. Without a
    requested breed the pig is a Large White, and without a requested age
    an adult, as in the original. A boar has heavier shoulders and a
    neck shield, small tusks, a sheath and testes; a sow a teat row and a
    belly that sags with age. A piglet has a big head and ears, a short
    snout and body, and fine hair.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and breed.

    Returns:
        The traits.

    Raises:
        Error: If the requested breed is not one of the six.
    """
    var requested = options.variant.value
    if requested >= 6:
        raise Error("The pig has no such breed")
    var seed = draw_u32(r) ^ imul32(options.seed, 0x9E3779B1) ^ 0x5BD1E995
    var R = stream_of(seed)
    var variant = requested if requested >= 0 else LARGEWHITE
    var sex = options.sex
    if sex != MALE and sex != FEMALE:
        sex = FEMALE if R.next() < 0.6 else MALE
    var age = JUVENILE if options.age == JUVENILE else ADULT
    var t = Traits(sex, age, variant)
    var piglet = age == JUVENILE
    var male = sex == MALE
    var h0: List[Float64] = [0.7, 0.68, 0.72, 0.7, 0.64, 0.7]
    var h1: List[Float64] = [0.9, 0.88, 0.92, 0.88, 0.82, 0.88]
    var mature = 0.0 if piglet else pow(R.next(), 1.4)
    var boar = 0.5 + 0.5 * mature if male and not piglet else 0.0
    var href = h0[variant] + (h1[variant] - h0[variant]) * mature
    var size: Float64
    if piglet:
        size = 0.36 + 0.14 * R.next()
    else:
        size = (href / 0.74) * (1.06 if male else 1.0) * (1.0 + 0.03 * R.g())
    var belly = 0.1
    if not male and not piglet:
        belly = 0.2 + 0.45 * mature * (0.6 + 0.4 * R.next())
    var ear = _ear_type(variant)
    var erect = ear == ERECT
    var ear_size: List[Float64] = [1.0, 1.05, 0.95, 0.9, 0.9, 1.0]
    var es = ear_size[variant] * (1.0 + 0.06 * R.g())
    if piglet:
        es *= 1.12 if erect else 1.02
    t.set("size", size)
    t.set("boar", boar)
    t.set("mature", mature)
    t.set("belly", belly)
    t.set("fat", 1.0 + 0.04 * R.g() + 0.03 * mature)
    var hams: List[Float64] = [1.0, 0.95, 1.1, 1.08, 1.02, 1.0]
    t.set(
        "ham", hams[variant] * (1.0 + 0.05 * R.g()) * (1.06 if piglet else 1.0)
    )
    t.set("ear", Float64(ear))
    t.set("earSize", es)
    var wide = piglet and erect
    t.set("earWide", 1.18 if wide else 1.0)
    t.set("earFwd", 0.5 * R.g())
    t.set("earOut", 0.6 * R.g() + (0.6 if wide else 0.0))
    var dish: List[Float64] = [0.35, 0.0, 0.25, 0.15, 0.9, 0.2]
    t.set(
        "dish",
        dish[variant] * (0.8 + 0.4 * R.next()) + (0.1 if piglet else 0.0),
    )
    var snout: List[Float64] = [1.0, 1.1, 1.0, 1.02, 0.86, 1.0]
    t.set(
        "snoutLen",
        snout[variant] * (1.0 + 0.04 * R.g()) * (0.85 if piglet else 1.0),
    )
    var adult_male = male and not piglet
    t.set(
        "tusks",
        0.35 + 0.65 * mature * (0.7 + 0.3 * R.next()) if adult_male else 0.0,
    )
    var teats = 7.0
    if R.next() >= 0.5:
        teats = 6.0 if R.next() < 0.7 else 8.0
    t.set("teats", teats)
    t.set("tailSide", 1.0 if R.next() < 0.5 else -1.0)
    t.set(
        "wrinkles",
        0.3 + 0.5 * mature + (0.2 if variant == BERKSHIRE else 0.0),
    )
    t.set("bristle", (1.0 + 0.15 * R.g()) * (1.2 if male else 1.0))
    var mud = 0.0
    if R.next() < 0.35:
        mud = 0.35 + 0.6 * R.next()
    t.set("mud", mud)
    t.set("beltFront", -0.055 + 0.012 * R.g())
    t.set("beltBack", 0.02 + 0.04 * R.g())
    t.set("blaze", 0.6 + 0.6 * R.next())
    t.set("socks", 0.8 + 0.5 * R.next())
    t.set("spotCount", Float64(5 + Int(R.next() * 7.0)))
    t.set("spotSize", 0.8 + 0.5 * R.next())
    t.set("coatShade", R.g())
    t.set("coatLightness", 0.05 * R.g())
    t.set("coatSeed", Float64(Int(R.next() * 1e6)))
    t.set("minThick", 0.0027)
    t.set("tierRes", options.quality.resolution())
    var head_k = (
        1.13
        * (1.0 + 0.03 * R.g())
        * (1.24 if piglet else 1.0)
        * (1.05 if adult_male else 1.0)
    )
    t.warps.add(scale_about_warp(HEAD_O, head_k, 0.12, 0.24))
    var legs: List[Float64] = [1.0, 0.98, 1.02, 1.0, 0.96, 0.98]
    var legs_k = (
        1.06 * legs[variant] * (1.0 + 0.045 * R.g()) * (1.19 if piglet else 1.0)
    )
    t.warps.add(legs_warp(legs_k, 0.36))
    var lens: List[Float64] = [1.0, 1.08, 0.98, 0.98, 0.96, 1.0]
    var len_k = (
        0.95
        * lens[variant]
        * (1.0 + 0.045 * R.g())
        * (1.16 if piglet else 1.0)
        * (1.0 + 0.03 * mature)
    )
    t.warps.add(length_warp(len_k, -0.42, 0.3))
    var girths: List[Float64] = [1.0, 0.97, 1.04, 1.02, 1.03, 1.05]
    var girth_k = (
        girths[variant]
        * (1.0 + 0.06 * R.g())
        * (0.95 if piglet else 1.0)
        * (1.0 + 0.04 * mature)
    )
    t.warps.add(girth_warp(girth_k, 0.52, -0.55, 0.36))
    if boar > 0.0:
        t.warps.add(girth_warp(1.0 + 0.07 * boar, 0.55, 0.12, 0.5))
    return t^


def _eye_dir() -> V3:
    var f = _frame()
    var a = 40.0 * pi / 180.0
    return normalize(V3(cos(a), 0.0, 0.0) + f.hz * sin(a) + f.hy * 0.1)


def pig_eye(t: Traits) -> EyeSpec:
    """Return the pig's left eye: a small almond under a fat-padded brow,
    the upper lid hooding the top of the iris.

    Args:
        t: The individual. The eye is the same in every pig.

    Returns:
        The eye, head-local.
    """
    _ = t
    var dir = _eye_dir()
    return EyeSpec(
        _hl(V3(0.058, 0.026, 0.006)) - HEAD_O + dir * 0.016,
        0.0128,
        0.003,
        atan2(dir.x, dir.z),
        asin(dir.y),
        0.0028,
        0.0112,
        0.006,
        0.0006,
        0.1,
        0.0074,
        0.0088,
    )


# ---------------------------------------------------------------- EARS


@fieldwise_init
struct EarForm(ImplicitlyCopyable):
    """One pig ear's form: its root, facing, bend, cup, size and tiles.

    `root` and `facing` are world directions of the standing pig's left
    ear. The spine bends toward the hollow by `bend` degrees from `s0` on
    (`bend_pow` makes it late), and sweeps by `sweep` degrees from
    `sweep_s0` on. The cross-section rolls by `cup_root` to `cup_tip`.
    `thick_root` and `thick_rim` are full thicknesses. `ns` by `na` tiles.
    """

    var root: V3
    var len: Float64
    var facing: V3
    var bend: Float64
    var s0: Float64
    var bend_pow: Float64
    var sweep: Float64
    var sweep_s0: Float64
    var sweep_pow: Float64
    var cup_root: Float64
    var cup_tip: Float64
    var width: Float64
    var thick_root: Float64
    var thick_rim: Float64
    var wave: Float64
    var ns: Int
    var na: Int


def _from_head(v: V3) -> V3:
    var hp = HEAD_PITCH * pi / 180.0
    return V3(v.x, v.y * cos(hp) - v.z * sin(hp), v.y * sin(hp) + v.z * cos(hp))


def _ear_form(ear: Int) -> EarForm:
    if ear == SEMI:
        return EarForm(
            V3(0.9, 0.0, 0.45),
            0.235,
            V3(0.1, -0.45, 1.0),
            45.0,
            0.4,
            1.2,
            75.0,
            0.2,
            1.3,
            0.7,
            0.35,
            0.29,
            0.014,
            0.0055,
            0.0,
            22,
            10,
        )
    if ear == LOP:
        return EarForm(
            _from_head(V3(0.3, 0.55, 0.78)),
            0.22,
            _from_head(V3(-0.5, -0.85, 0.15)),
            95.0,
            0.3,
            1.5,
            0.0,
            0.3,
            1.0,
            0.45,
            0.2,
            0.28,
            0.015,
            0.0055,
            0.015,
            14,
            10,
        )
    return EarForm(
        V3(0.58, 0.8, 0.2),
        0.2,
        V3(0.45, -0.4, 0.9),
        12.0,
        0.1,
        2.0,
        0.0,
        0.1,
        1.0,
        0.95,
        0.28,
        0.41,
        0.012,
        0.0055,
        0.0,
        12,
        10,
    )


def _ear_w(ear: Int, u: Float64) -> Float64:
    # The leaf's half width along it, as a fraction of its width.
    var ts: List[Float64]
    var ws: List[Float64]
    if ear == SEMI:
        ts = [0.0, 0.08, 0.24, 0.45, 0.66, 0.84, 0.95, 1.0]
        ws = [0.5, 0.7, 0.95, 1.0, 0.9, 0.64, 0.36, 0.12]
    elif ear == LOP:
        ts = [0.0, 0.08, 0.24, 0.46, 0.66, 0.84, 0.95, 1.0]
        ws = [0.46, 0.64, 0.9, 1.0, 0.92, 0.66, 0.36, 0.1]
    else:
        ts = [0.0, 0.08, 0.22, 0.4, 0.6, 0.78, 0.9, 1.0]
        ws = [0.5, 0.68, 0.94, 1.0, 0.9, 0.66, 0.38, 0.06]
    for i in range(1, len(ts)):
        if u <= ts[i]:
            return ws[i - 1] + (ws[i] - ws[i - 1]) * (u - ts[i - 1]) / (
                ts[i] - ts[i - 1]
            )
    return ws[len(ws) - 1]


@fieldwise_init
struct EarSpine(Copyable, Movable):
    """One ear leaf's spine: stations from the root and their frames.

    `d` runs along the spine, `h` toward the hollow side and `l` across
    the leaf. `width` is the leaf's full width and `len` its length.
    """

    var pts: List[V3]
    var d: List[V3]
    var h: List[V3]
    var l: List[V3]
    var len: Float64
    var width: Float64
    var tip: V3


comptime EAR_STEPS = 96


def _ramp(u: Float64, u0: Float64, p: Float64) -> Float64:
    return pow(clamp((u - u0) / (1.0 - u0), 0.0, 1.0), p)


def _ear_spine(base: V3, s: Float64, t: Traits) -> EarSpine:
    # The leaf leaves the head along its root direction, runs straight
    # for a while and then folds toward its hollow, sweeping in its plane.
    var ear = Int(t.get("ear", 0.0))
    var f = _ear_form(ear)
    var d = normalize(f.root)
    var dir = normalize(
        V3(
            d.x + 0.25 * t.get("earOut", 0.0),
            d.y,
            d.z + 0.35 * t.get("earFwd", 0.0),
        )
    )
    var ln = f.len * t.get("earSize", 1.0)
    var d0 = V3(dir.x * s, dir.y, dir.z)
    var fw = V3(f.facing.x * s, f.facing.y, f.facing.z)
    var f0 = normalize(fw - d0 * dot(fw, d0))
    var lat = normalize(cross(d0, f0))
    var bend = f.bend * pi / 180.0
    var sweep = f.sweep * pi / 180.0 * s
    var out = EarSpine(
        [base],
        [d0],
        [f0],
        [lat],
        ln,
        f.width * ln * t.get("earWide", 1.0),
        base,
    )
    var o = base
    var dd = d0
    var hh = f0
    var ll = lat
    for k in range(1, EAR_STEPS + 1):
        var u0 = Float64(k - 1) / Float64(EAR_STEPS)
        var u1 = Float64(k) / Float64(EAR_STEPS)
        var da = bend * (
            _ramp(u1, f.s0, f.bend_pow) - _ramp(u0, f.s0, f.bend_pow)
        )
        var db = sweep * (
            _ramp(u1, f.sweep_s0, f.sweep_pow)
            - _ramp(u0, f.sweep_s0, f.sweep_pow)
        )
        var prev = dd
        var d2 = dd * cos(da) + hh * sin(da)
        hh = hh * cos(da) - dd * sin(da)
        dd = d2
        d2 = dd * cos(db) + ll * sin(db)
        dd = normalize(d2)
        hh = normalize(hh - dd * dot(hh, dd))
        ll = cross(dd, hh)
        o = o + normalize(prev + dd) * (ln / Float64(EAR_STEPS))
        out.pts.append(o)
        out.d.append(dd)
        out.h.append(hh)
        out.l.append(ll)
    out.tip = o
    return out^


def _leaf_point(
    sp: EarSpine, f: EarForm, ear: Int, wph: Float64, kf: Float64, a: Float64
) -> Tuple[V3, V3]:
    # The leaf's mid-surface point and its hollow-side normal at station
    # `kf` and across `a` from -1 to 1.
    var k = min(EAR_STEPS - 1, max(0, Int(floor(kf))))
    var fr = kf - Float64(k)
    var h = normalize(sp.h[k] * (1.0 - fr) + sp.h[k + 1] * fr)
    var l = normalize(sp.l[k] * (1.0 - fr) + sp.l[k + 1] * fr)
    var p = sp.pts[k] * (1.0 - fr) + sp.pts[k + 1] * fr
    var u = kf / Float64(EAR_STEPS)
    var w = max(
        1e-4,
        _ear_w(ear, u)
        * sp.width
        * (
            1.0
            + f.wave * sin(2.0 * pi * 3.4 * u + wph) * smoothstep(0.1, 0.35, u)
        ),
    )
    var cup = f.cup_root + (f.cup_tip - f.cup_root) * u
    var kap = cup / w
    var x = a * w
    var q = p + l * (sin(kap * x) / kap) + h * ((1.0 - cos(kap * x)) / kap)
    var n = normalize(h * cos(kap * x) - l * sin(kap * x))
    return (q, n)


def _leaf_thick(f: EarForm, u: Float64, a: Float64, t_min: Float64) -> Float64:
    var tr = f.thick_root
    var te = f.thick_rim
    var th = te + (tr - te) * (1.0 - smoothstep(0.0, 0.55, u)) * (
        1.0 - smoothstep(0.25, 1.0, abs(a))
    )
    return max(th, t_min)


def _ear_leaf(
    mut m: SdfModel, bone: BoneId, base: V3, s: Float64, t: Traits
) raises:
    # The leaf: one smooth curved sheet, thick at the root and thinning
    # toward a round rim. The original tiles it with slabs curved to the
    # sheet; flat slabs facet it, so here each close-spaced station along
    # the spine is a chain of round cones across the cupped section, the
    # stations blended into one sheet.
    var ear = Int(t.get("ear", 0.0))
    var f = _ear_form(ear)
    var sp = _ear_spine(base, s, t)
    var res = t.get("tierRes", 1.0)
    var t_min = (2.3 if res >= 1.9 else 1.8) * CELL * res
    var wph = Float64(Int(t.get("coatSeed", 0.0)) % 628) / 100.0 + (
        0.0 if s > 0.0 else 2.1
    )
    var rows = 3 * f.ns + 6
    var across: List[Float64] = [-0.92, -0.3, 0.3, 0.92]
    for i in range(rows):
        var u = (Float64(i) + 0.5) / Float64(rows)
        var kf = u * Float64(EAR_STEPS)
        for j in range(len(across) - 1):
            var a0 = across[j]
            var a1 = across[j + 1]
            var p0 = _leaf_point(sp, f, ear, wph, kf, a0)[0]
            var p1 = _leaf_point(sp, f, ear, wph, kf, a1)[0]
            var r0 = _leaf_thick(f, u, a0, t_min) / 2.0
            var r1 = _leaf_thick(f, u, a1, t_min) / 2.0
            var ok = length(p1 - p0) > abs(r1 - r0) + 1e-5
            if ok:
                _ = m.cone("ear", bone, p0, p1, r0, r1, k=0.006, part=EAR)


# ---------------------------------------------------------------- TAIL


def _pig_tail(mut rig: Rig, side: Float64) raises:
    # The corkscrew: every joint turns by the same rotation, a helix that
    # rolls down behind the buttocks and drifts to one side.
    var lens: List[Float64] = [
        0.052,
        0.03,
        0.025,
        0.023,
        0.022,
        0.021,
        0.02,
        0.019,
        0.018,
        0.017,
    ]
    var r0 = 4.0 * pi / 180.0
    var y = V3(0.0, sin(r0), -cos(r0))
    var x = V3(1.0, 0.0, 0.0)
    var beta = 58.0 * pi / 180.0
    var tau = 0.45 * side
    var p = rig.j("tailBase")
    rig.set("tail0", p)
    for i in range(TAIL_SEGS):
        p = p + y * lens[i]
        rig.set("tail" + String(i + 1), p)
        var ax = normalize(x * cos(tau) + y * sin(tau))
        var b = beta * (0.6 if i == 0 else 1.0)
        y = rotate_about(y, ax, b)
        x = rotate_about(x, ax, b)


def pig_rig(t: Traits) raises -> Rig:
    """Return the pig's skeleton in bind pose.

    The hoofed quadruped with a snout bone carrying the rostral disc, and
    a corkscrew tail of ten bones.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var k = t.get("snoutLen", 1.0) * SNOUT_K
    var rig = Rig()
    rig.set("nose", _hl(V3(0.0, -0.012, _sz(0.198, k))))
    rig.set("snoutBase", _hl(V3(0.0, 0.0, _sz(0.12, k))))
    rig.set("occiput", _hl(V3(0.0, -0.015, -0.115)))
    rig.set("neckMid", V3(0.0, 0.59, 0.415))
    rig.set("neckBase", V3(0.0, 0.56, 0.33))
    rig.set("chestMid", V3(0.0, 0.625, 0.16))
    rig.set("thoraxRear", V3(0.0, 0.645, -0.02))
    rig.set("lumbarMid", V3(0.0, 0.655, -0.19))
    rig.set("lumbosacral", V3(0.0, 0.66, -0.36))
    rig.set("tailBase", V3(0.0, 0.69, -0.59))
    rig.set("scapTopL", V3(0.065, 0.66, 0.255))
    rig.set("shoulderL", V3(0.105, 0.48, 0.395))
    rig.set("elbowL", V3(0.1, 0.31, 0.29))
    rig.set("wristL", V3(0.088, 0.15, 0.305))
    rig.set("mcpL", V3(0.083, 0.064, 0.322))
    rig.set("fcoffinL", V3(0.083, 0.028, 0.345))
    rig.set("ftoeL", V3(0.083, 0.002, 0.388))
    rig.set("hipL", V3(0.09, 0.55, -0.4))
    rig.set("kneeL", V3(0.11, 0.36, -0.27))
    rig.set("hockL", V3(0.086, 0.17, -0.395))
    rig.set("mtpL", V3(0.082, 0.064, -0.362))
    rig.set("hcoffinL", V3(0.082, 0.028, -0.338))
    rig.set("htoeL", V3(0.082, 0.002, -0.296))
    rig.set("jawHinge", _hl(V3(0.0, -0.052, -0.06)))
    rig.set("jawTip", _hl(V3(0.0, -0.085, _sz(0.15, k))))
    var eb = _hl(EAR_BASE)
    rig.set("earBaseL", eb)
    rig.set("earTipL", _ear_spine(eb, 1.0, t).tip)
    _pig_tail(rig, t.get("tailSide", 1.0))
    rig.mirror_joints()
    hoofed_bones(rig, TAIL_SEGS, snout=True)
    return rig^


def _sz(z: Float64, k: Float64) -> Float64:
    # The snout's length: the rostral end moves, the eyes stay.
    return 0.06 + (z - 0.06) * k if z > 0.06 else z


# ---------------------------------------------------------------- SCULPT


def _hell(
    mut m: SdfModel,
    h: BoneId,
    tag: String,
    c: V3,
    r: V3,
    k: Float64,
    carve: Bool = False,
) raises:
    var f = _frame()
    _ = m.ell(tag, h, f.at_chained(c), r, axis=f.hz, up=f.hy, k=k, carve=carve)


def _tusk_cones(t: Traits, s: Float64) -> List[V3]:
    # The tusk's center line as a cubic Bezier, as cone ends and radii:
    # each entry is (a, b, (ra, rb, 0)).
    var tl = t.get("tusks", 0.0)
    var p0 = lerp(
        _hl(V3(0.03 * s, -0.078, 0.128)),
        _hl(V3(0.066 * s, -0.066, 0.132)),
        0.55,
    )
    var p1 = _hl(V3(0.066 * s, -0.066, 0.132))
    var p2 = _hl(V3(0.077 * s, -0.052 + 0.014 * tl, 0.13 - 0.008 * tl))
    var p3 = _hl(V3(0.082 * s, -0.05 + 0.04 * tl, 0.127 - 0.04 * tl))
    var r0 = 0.0045 + 0.0025 * tl
    var r1 = 0.0012
    var out = List[V3]()
    for i in range(8):
        var t0 = Float64(i) / 8.0
        var t1 = Float64(i + 1) / 8.0
        out.append(_bezier(p0, p1, p2, p3, t0))
        out.append(_bezier(p0, p1, p2, p3, t1))
        out.append(
            V3(
                r1 + (r0 - r1) * (1.0 - pow(t0, 1.3)),
                r1 + (r0 - r1) * (1.0 - pow(t1, 1.3)),
                0.0,
            )
        )
    return out^


def _bezier(p0: V3, p1: V3, p2: V3, p3: V3, t: Float64) -> V3:
    var u = 1.0 - t
    return (
        p0 * (u * u * u)
        + p1 * (3.0 * u * u * t)
        + p2 * (3.0 * u * t * t)
        + p3 * (t * t * t)
    )


def _pig_eye(mut m: SdfModel, h: BoneId, e: EyeSpec, s: Float64) raises:
    # The eye in its socket: an orbit hollow, the lid shell, a roll of
    # the upper lid and a slimmer lower lid, and the almond cut through.
    var ef = eye_frame_of(e, HEAD_O, s)
    _ = m.ell(
        "orbit",
        h,
        ef.at(0, 0.0015, 0.014),
        V3(0.016, 0.0115, 0.008),
        axis=ef.z,
        up=ef.y,
        k=0.011,
        carve=True,
    )
    _ = m.sphere("eyelid", h, ef.c, e.r + e.lid, k=e.r * 0.4)
    var hh = e.big_r - e.d
    var rl = e.r + e.lid
    var yu = e.off + hh + 0.0016
    _ = m.ell(
        "lidroll",
        h,
        ef.at(0, yu, sqrt(max(0.0, rl * rl - yu * yu)) - 0.0012),
        V3(0.0105, 0.0032, 0.0028),
        axis=ef.z,
        up=ef.y,
        k=0.003,
    )
    var yl = e.off - hh - 0.0012
    _ = m.ell(
        "lidroll",
        h,
        ef.at(0, yl, sqrt(max(0.0, rl * rl - yl * yl)) - 0.0017),
        V3(0.0088, 0.0028, 0.0026),
        axis=ef.z,
        up=ef.y,
        k=0.0035,
    )
    _ = m.lens(
        "eyesocket",
        h,
        ef.c + ef.y * e.off,
        ef.x,
        ef.y,
        ef.z,
        e.big_r,
        e.d,
        -e.r * 0.16,
        e.r * 2.0,
        k=e.r * 0.18,
        carve=True,
    )


def pig_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the pig: procedural-animals' `sculptPig`, primitive for
    primitive, with its ear leaves from `ears.js`.

    Args:
        m: The sculpt to add to.
        rig: The pig's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var piglet = t.juvenile() > 0.0
    var boar = t.get("boar", 0.0)
    var belly = t.get("belly", 0.3)
    var ham_k = t.get("ham", 1.0)
    var fat = t.get("fat", 1.0)
    var snout_k = t.get("snoutLen", 1.0) * SNOUT_K
    var dish = t.get("dish", 0.2)
    var f = _frame()

    # TORSO: one long barrel, shoulders, back and hams in one mass.
    var wb = (1.0 + 0.05 * boar) * fat
    var tuck = 0.03 if piglet else 0.0
    var sp2 = rig.bone("spine2")
    var pel = rig.bone("pelvis")
    _ = m.ell(
        "barrel",
        sp2,
        V3(0, 0.525 + tuck / 2.0, -0.08),
        V3(0.186 * wb, 0.2 - tuck / 2.0, 0.5),
        k=0,
    )
    _ = m.ell(
        "ribs",
        sp2,
        V3(0, 0.535 + tuck / 2.0, -0.055),
        V3(0.21 * wb, 0.15, 0.295),
        k=0.07,
    )
    _ = m.ell(
        "shoulder",
        rig.bone("spine3"),
        V3(0, 0.535 + tuck / 2.0, 0.21),
        V3(0.166 * wb + 0.012 * boar, 0.178 + 0.01 * boar - tuck / 2.0, 0.2),
        k=0.08,
    )
    _ = m.ell(
        "hamball",
        pel,
        V3(0, 0.53 + tuck / 3.0, -0.43),
        V3(
            0.172 * wb * (0.94 + 0.06 * ham_k),
            0.195 - tuck / 3.0,
            0.2 * (0.95 + 0.05 * ham_k),
        ),
        k=0.08,
    )
    _ = m.ell(
        "back", sp2, V3(0, 0.665, -0.08), V3(0.132 * wb, 0.07, 0.44), k=0.1
    )
    _ = m.ell(
        "rump",
        pel,
        V3(0, 0.665, -0.4),
        V3(0.13 * wb, 0.07, 0.18),
        axis=normalize(V3(0, -0.1, 1)),
        k=0.08,
    )
    _ = m.ell(
        "belly",
        sp2,
        V3(0, 0.398 - 0.04 * belly + tuck, -0.1),
        V3(0.148 * wb, 0.08 + 0.022 * belly, 0.33),
        k=0.1,
    )
    _ = m.ell(
        "brisket",
        rig.bone("chest"),
        V3(0, 0.445 + tuck * 0.8, 0.3),
        V3(0.105, 0.095, 0.11),
        k=0.06,
    )
    _ = m.ell(
        "buttock", pel, V3(0, 0.6, -0.54), V3(0.12 * wb, 0.11, 0.08), k=0.08
    )
    _ = m.ell(
        "tailroot", pel, V3(0, 0.675, -0.575), V3(0.04, 0.035, 0.035), k=0.05
    )
    var mature_boar = boar >= 0.5 and not piglet
    if mature_boar:
        for s in [1.0, -1.0]:
            _ = m.ell(
                "scrotum",
                pel,
                V3(0.038 * s, 0.5, -0.585),
                V3(0.045, 0.06, 0.045),
                k=0.04,
            )
        _ = m.ell(
            "sheath",
            sp2,
            V3(0, 0.305, -0.02),
            V3(0.028, 0.03, 0.07),
            axis=normalize(V3(0, 0.25, 1)),
            k=0.05,
        )

    # NECK: short and thick, hidden in the jowls.
    var nk = 1.0 + 0.25 * boar
    var n1 = rig.bone("neck1")
    var n2 = rig.bone("neck2")
    _ = m.ell(
        "neck",
        n1,
        V3(0, 0.54, 0.38),
        V3(0.14 * nk * fat, 0.16, 0.13),
        axis=normalize(V3(0, 0.3, 1)),
        k=0.1,
    )
    _ = m.ell(
        "neck",
        n2,
        V3(0, 0.56, 0.45),
        V3(0.12 * nk * fat, 0.13, 0.1),
        axis=normalize(V3(0, 0.4, 1)),
        k=0.08,
    )
    _ = m.ell(
        "nape",
        n1,
        V3(0, 0.655 + 0.012 * boar, 0.39),
        V3(0.1 * nk, 0.065 + 0.012 * boar, 0.14),
        axis=normalize(V3(0, -0.12, 1)),
        k=0.09,
    )
    _ = m.cone(
        "throat",
        n1,
        V3(0, 0.43, 0.36),
        V3(0, 0.46, 0.44),
        0.085 * fat,
        0.08,
        k=0.09,
    )
    _ = m.cone(
        "throat",
        n2,
        V3(0, 0.46, 0.44),
        _hl(V3(0, -0.115, -0.03)),
        0.075,
        0.06,
        k=0.08,
    )

    # HEAD, head-local: a broad skull, a slightly dished bridge, the disc.
    var h = rig.bone("head")
    var hb = 1.0 + 0.08 * boar
    _hell(
        m, h, "cranium", V3(0, 0.008, -0.06), V3(0.088 * hb, 0.064, 0.085), 0.05
    )
    _hell(m, h, "poll", V3(0, 0.042, -0.08), V3(0.075 * hb, 0.04, 0.05), 0.04)
    _hell(m, h, "forehead", V3(0, 0.036, 0.01), V3(0.074, 0.03, 0.08), 0.04)
    _ = m.cone(
        "snout",
        h,
        _hl(V3(0, -0.004, 0.05)),
        _hl(V3(0, -0.007, _sz(0.16, snout_k))),
        0.057,
        0.05,
        k=0.04,
    )
    _hell(
        m,
        h,
        "nasal",
        V3(0, 0.018, _sz(0.1, snout_k)),
        V3(0.05, 0.022, 0.07 * snout_k),
        0.03,
    )
    if dish > 0.01:
        _hell(
            m,
            h,
            "dish",
            V3(0, 0.089 - 0.02 * dish, _sz(0.11, snout_k)),
            V3(0.11, 0.04, 0.075 * snout_k),
            0.03,
            carve=True,
        )
    _hell(m, h, "muzzle", V3(0, -0.03, 0.05), V3(0.064 * hb, 0.05, 0.09), 0.04)
    var eye = pig_eye(t)
    for s in [1.0, -1.0]:
        _hell(
            m,
            h,
            "jowl",
            V3(0.066 * s * hb, -0.075, -0.035),
            V3(0.06 * hb * fat, 0.08, 0.085),
            0.05,
        )
        _hell(
            m,
            h,
            "cheek",
            V3(0.07 * s, -0.01, -0.05),
            V3(0.05 * fat, 0.055, 0.07),
            0.03,
        )
        _ = m.cone(
            "lip",
            h,
            _hl(V3(0.058 * s, -0.058, 0.045)),
            _hl(V3(0.042 * s, -0.042, _sz(0.155, snout_k))),
            0.03,
            0.02,
            k=0.03,
        )
        _hell(
            m,
            h,
            "brow",
            V3(0.058 * s, 0.05, 0.0),
            V3(0.022, 0.012, 0.03),
            0.025,
        )
        _pig_eye(m, h, eye, s)
        var eb = rig.j("earBase" + ("L" if s > 0.0 else "R"))
        _ = m.sphere(
            "earbase", h, eb + V3(-0.014 * s, -0.006, 0), 0.02, k=0.045
        )
    if boar > 0.0:
        for s in [1.0, -1.0]:
            _hell(
                m,
                h,
                "jowl",
                V3(0.06 * s, -0.09, -0.06),
                V3(0.04 * boar, 0.05 * boar, 0.06),
                0.05,
            )
        for s in [1.0, -1.0]:
            _hell(
                m,
                h,
                "lip",
                V3(0.036 * s, -0.04, _sz(0.105, snout_k)),
                V3(0.014, 0.018, 0.026),
                0.025,
            )
    _hell(m, h, "underjaw", V3(0, -0.083, 0.0), V3(0.05, 0.028, 0.06), 0.04)
    var jw = rig.bone("jaw")
    var zx = _sz(0.105, snout_k)
    var zc = 0.02
    var rz = zx + 0.025 - zc
    var uu = (zx - zc) / rz
    var ry = 0.018
    _ = m.ell(
        "underjaw",
        jw,
        _hl(V3(0, -0.1045 + ry * sqrt(1.0 - uu * uu), zc)),
        V3(0.054, ry, rz),
        axis=f.hz,
        up=f.hy,
        k=0.03,
    )

    # The rostral disc, on its own bone: a flat oval plate with a rim.
    var sn = rig.bone("snout")
    var dz = _sz(0.178, snout_k)
    _ = m.ell(
        "disc",
        sn,
        _hl(V3(0, -0.006, dz)),
        V3(0.058, 0.045, 0.026),
        axis=f.hz,
        up=f.hy,
        k=0.012,
    )
    _ = m.cone(
        "snoutend",
        sn,
        _hl(V3(0, -0.006, _sz(0.13, snout_k))),
        _hl(V3(0, -0.006, dz - 0.008)),
        0.049,
        0.048,
        k=0.02,
    )
    _ = m.sphere(
        "discface",
        sn,
        _hl(V3(0, -0.006, dz + 0.012 + 0.4)),
        0.4,
        k=0.004,
        carve=True,
    )
    for s in [1.0, -1.0]:
        var a = 0.4 * s
        var up = V3(-sin(a), cos(a) * f.hy.y, cos(a) * f.hy.z)
        _ = m.ell(
            "nostril",
            sn,
            _hl(V3(0.025 * s, -0.009, dz + 0.012)),
            V3(0.0135, 0.0088, 0.017),
            axis=f.hz,
            up=up,
            k=0.005,
            carve=True,
        )

    # JAW: the lower lip, the chin and the tongue.
    _ = m.ell(
        "chin",
        jw,
        _hl(V3(0, -0.077, _sz(0.09, snout_k))),
        V3(0.04, 0.027, 0.064 * snout_k),
        axis=f.hz,
        up=f.hy,
        k=0,
        part=JAW,
    )
    _ = m.ell(
        "lowerlip",
        jw,
        _hl(V3(0, -0.067, _sz(0.122, snout_k))),
        V3(0.026, 0.015, 0.02),
        axis=f.hz,
        up=f.hy,
        k=0.015,
        part=JAW,
    )
    _ = m.ell(
        "tongue",
        jw,
        _hl(V3(0, -0.053, _sz(0.085, snout_k))),
        V3(0.024, 0.011, 0.05 * snout_k),
        axis=f.hz,
        up=f.hy,
        k=0.012,
        part=JAW,
    )
    for s in [1.0, -1.0]:
        _ = m.cone(
            "mandible",
            jw,
            _hl(V3(0.032 * s, -0.08, 0.02)),
            _hl(V3(0.026 * s, -0.076, _sz(0.13, snout_k))),
            0.02,
            0.016,
            k=0.02,
            part=JAW,
        )
    if t.get("tusks", 0.0) > 0.05:
        for s in [1.0, -1.0]:
            var cones = _tusk_cones(t, s)
            for i in range(len(cones) // 3):
                _ = m.cone(
                    "tusk",
                    jw,
                    cones[3 * i],
                    cones[3 * i + 1],
                    cones[3 * i + 2].x,
                    cones[3 * i + 2].y,
                    k=0,
                    part=TEETH,
                )

    # EARS: curved leaves tiled with slabs.
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        _ear_leaf(m, rig.bone("ear" + side), rig.j("earBase" + side), s, t)

    # LEGS: short and sunk in the body.
    var leg_k = (1.0 + 0.1 * boar) * (1.05 if piglet else 1.0)
    for side in [String("L"), String("R")]:
        var s = 1.0 if side == "L" else -1.0
        var lat = V3(s, 0, 0)
        var sc = rig.j("scapTop" + side)
        var sh = rig.j("shoulder" + side)
        var e = rig.j("elbow" + side)
        var w = rig.j("wrist" + side)
        var mc = rig.j("mcp" + side)
        var cf = rig.j("fcoffin" + side)
        var toe = rig.j("ftoe" + side)
        var hum = rig.bone("humerus" + side)
        var rad = rig.bone("radius" + side)
        var meta = rig.bone("metacarpus" + side)
        _ = ell_y(
            m,
            "scapmuscle",
            rig.bone("scapula" + side),
            lerp(sc, sh, 0.5) + V3(0.055 * s, 0, -0.01),
            sh - sc,
            V3(0.06 + 0.02 * boar, 0.15, 0.11),
            lateral=lat,
            k=0.1,
        )
        _ = m.sphere(
            "shoulderpoint",
            hum,
            sh + V3(0.02 * s, 0.0, 0.01),
            0.06 * leg_k,
            k=0.08,
        )
        _ = m.cone("upperarm", hum, sh, e, 0.072 * leg_k, 0.058 * leg_k, k=0.08)
        _ = ell_y(
            m,
            "triceps",
            hum,
            lerp(sh, e, 0.55) + V3(0.012 * s, 0.0, -0.055),
            e - sh,
            V3(0.062 * leg_k, 0.1, 0.075),
            lateral=lat,
            k=0.08,
        )
        _ = m.sphere("olecranon", rad, e + V3(0, 0.015, -0.04), 0.035, k=0.04)
        _ = m.cone(
            "forearm",
            rad,
            e + V3(0, 0, -0.005),
            w,
            0.05 * leg_k,
            0.029 * leg_k,
            k=0.04,
        )
        _ = ell_y(
            m,
            "forearmmuscle",
            rad,
            lerp(e, w, 0.25) + V3(0.006 * s, 0, 0.008),
            w - e,
            V3(0.045 * leg_k, 0.075, 0.048 * leg_k),
            lateral=lat,
            k=0.04,
        )
        _ = m.cone(
            "forearmweb",
            rad,
            e + V3(-0.03 * s, 0.05, -0.01),
            lerp(e, w, 0.3) + V3(-0.012 * s, 0, 0),
            0.045,
            0.03,
            k=0.05,
        )
        _ = ell_y(
            m,
            "knee",
            meta,
            w + V3(0, 0, 0.002),
            V3(0, 1, 0),
            V3(0.03 * leg_k, 0.033, 0.029 * leg_k),
            lateral=lat,
            k=0.02,
        )
        _ = m.cone(
            "cannon",
            meta,
            w + V3(0, -0.012, 0),
            mc + V3(0, 0.01, -0.002),
            0.024 * leg_k,
            0.022 * leg_k,
            k=0.015,
        )
        _ = ell_y(
            m,
            "fetlock",
            meta,
            mc + V3(0, 0, -0.006),
            V3(0, 1, 0.3),
            V3(0.026 * leg_k, 0.026, 0.028),
            lateral=lat,
            k=0.015,
        )
        _digits(
            m,
            rig.bone("fpaw" + side),
            rig.bone("fhoof" + side),
            mc,
            cf,
            toe,
            leg_k,
        )

        var hp = rig.j("hip" + side)
        var kn = rig.j("knee" + side)
        var hk = rig.j("hock" + side)
        var mt = rig.j("mtp" + side)
        var chf = rig.j("hcoffin" + side)
        var tt = rig.j("htoe" + side)
        var fem = rig.bone("femur" + side)
        var tib = rig.bone("tibia" + side)
        var mtar = rig.bone("metatarsus" + side)
        _ = ell_y(
            m,
            "thigh",
            fem,
            lerp(hp, kn, 0.45) + V3(0.035 * s, 0, -0.045),
            kn - hp,
            V3(0.075 * ham_k, 0.18, 0.15 * ham_k),
            lateral=lat,
            k=0.1,
        )
        _ = m.cone(
            "thighfront",
            fem,
            V3(0.13 * s, 0.6, -0.3),
            kn + V3(0, 0.04, 0.03),
            0.08,
            0.055,
            k=0.08,
        )
        _ = m.cone(
            "ham",
            fem,
            V3(0.08 * s, 0.6, -0.56),
            lerp(kn, hk, 0.35) + V3(0, 0, -0.045),
            0.1 * ham_k,
            0.048,
            k=0.08,
        )
        _ = ell_y(
            m,
            "flankfold",
            fem,
            V3(0.13 * s, 0.4, -0.2),
            V3(-0.1, 0.3, 0.12),
            V3(0.04, 0.09, 0.06),
            lateral=lat,
            k=0.08,
        )
        _ = m.sphere(
            "stifle", tib, kn + V3(0.008 * s, 0.01, 0.02), 0.045, k=0.06
        )
        _ = ell_y(
            m,
            "gaskin",
            tib,
            lerp(kn, hk, 0.35) + V3(0.004 * s, 0, -0.03),
            hk - kn,
            V3(0.048 * leg_k, 0.095, 0.06 * leg_k),
            lateral=lat,
            k=0.05,
        )
        _ = m.cone(
            "shin",
            tib,
            lerp(kn, hk, 0.1),
            hk,
            0.042 * leg_k,
            0.029 * leg_k,
            k=0.04,
        )
        _ = m.cone(
            "achilles",
            tib,
            lerp(kn, hk, 0.45) + V3(0, 0, -0.045),
            hk + V3(0, 0.04, -0.04),
            0.02,
            0.016,
            k=0.025,
        )
        _ = m.sphere("calcaneus", mtar, hk + V3(0, 0.04, -0.038), 0.021, k=0.02)
        _ = ell_y(
            m,
            "hock",
            mtar,
            hk + V3(0, 0.006, -0.004),
            V3(0, 1, 0.25),
            V3(0.031 * leg_k, 0.042, 0.033),
            lateral=lat,
            k=0.02,
        )
        _ = m.cone(
            "cannon",
            mtar,
            hk + V3(0, -0.022, 0.003),
            mt + V3(0, 0.01, 0),
            0.024 * leg_k,
            0.022 * leg_k,
            k=0.015,
        )
        _ = ell_y(
            m,
            "fetlock",
            mtar,
            mt + V3(0, 0, -0.006),
            V3(0, 1, 0.3),
            V3(0.026 * leg_k, 0.026, 0.028),
            lateral=lat,
            k=0.015,
        )
        _digits(
            m,
            rig.bone("hpaw" + side),
            rig.bone("hhoof" + side),
            mt,
            chf,
            tt,
            leg_k * 0.98,
        )

    # TEATS: two rows along the belly.
    var pairs = Int(t.get("teats", 7.0))
    var teat_k = 0.45 if boar >= 0.5 else (0.5 if piglet else 0.8 + 0.6 * belly)
    for i in range(pairs):
        var z = 0.2 + (-0.34 - 0.2) * Float64(i) / Float64(max(1, pairs - 1))
        var yb = 0.3 - 0.03 * belly + 0.008 * abs(z + 0.08) * 4.0 * 0.3 + tuck
        var x = 0.052 + 0.01 * cos(
            (Float64(i) / Float64(pairs - 1) - 0.5) * 2.0
        )
        var bone = "spine3" if z > 0.05 else (
            "spine1" if z < -0.2 else "spine2"
        )
        for s in [1.0, -1.0]:
            _ = m.cone(
                "teat",
                rig.bone(bone),
                V3(x * s, yb + 0.02, z),
                V3(x * s * 1.02, yb - 0.012 * teat_k, z),
                0.0085 * max(0.6, teat_k),
                0.006 * max(0.6, teat_k),
                k=0.008,
            )

    # TAIL: thin, a corkscrew, its own surface.
    for i in range(TAIL_SEGS):
        var t0 = Float64(i) / Float64(TAIL_SEGS)
        var t1 = Float64(i + 1) / Float64(TAIL_SEGS)
        _ = m.cone(
            "tailtip" if i >= TAIL_SEGS - 1 else "tail",
            rig.bone("tail" + String(i)),
            rig.j("tail" + String(i)),
            rig.j("tail" + String(i + 1)),
            0.0115 - 0.0065 * pow(t0, 0.8),
            0.0115 - 0.0065 * pow(t1, 0.8),
            k=0.03 if i == 0 else 0.004,
            part=TAIL,
            thin=i > TAIL_SEGS // 2,
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
    # The pastern with two dew claws behind, then two claws flat on the
    # ground with a cleft between them and heel bulbs behind.
    _ = m.cone("pastern", paw, mc, c, 0.022 * w, 0.024 * w, k=0.012)
    for d in [1.0, -1.0]:
        var base = mc + V3(0.017 * d * w, -0.012, -0.022)
        _ = m.cone(
            "dewclaw",
            paw,
            base,
            base + V3(0.004 * d, -0.016, -0.012),
            0.0075 * w,
            0.004 * w,
            k=0.006,
        )
    var zmid = (c.z + toe.z) * 0.5
    var dir = 1.0 if toe.z > c.z else -1.0
    for d in [1.0, -1.0]:
        var off = 0.0145 * d * w
        var top = c + V3(off, 0.012, -0.008 * dir)
        var base = V3(c.x + off * 1.1, 0.0, zmid - 0.003 * dir)
        _ = m.cone("hoof", hoof, top, base, 0.0145 * w, 0.02 * w, k=0.007)
        _ = m.ell(
            "hoof",
            hoof,
            V3(c.x + off * 0.9, 0.013, toe.z - 0.016 * dir),
            V3(0.0135 * w, 0.0125, 0.02),
            axis=normalize(V3(0, -0.3, dir)),
            k=0.007,
        )
        _ = m.sphere(
            "heelbulb",
            hoof,
            c + V3(off * 0.9, -0.015, -0.024 * dir),
            0.0145 * w,
            k=0.011,
        )
    _ = m.cone(
        "coronet",
        hoof,
        c + V3(0, 0.014, -0.011 * dir),
        c + V3(0, 0.007, 0.011 * dir),
        0.024 * w,
        0.024 * w,
        k=0.009,
    )
    _ = m.ell(
        "cleft",
        hoof,
        V3(c.x, 0.0, toe.z - 0.002 * dir),
        V3(0.003, 0.026, 0.043),
        k=0.0025,
        carve=True,
    )
    _ = m.ell(
        "cleft",
        hoof,
        V3(c.x, -0.003, zmid),
        V3(0.0025, 0.017, 0.046),
        k=0.002,
        carve=True,
    )
    _ = m.ell(
        "sole",
        hoof,
        V3(c.x, -0.2 + 0.0015, zmid),
        V3(0.2, 0.2, 0.2),
        k=0.003,
        carve=True,
    )


# ---------------------------------------------------------------- COAT


def pig_look(t: Traits) -> EyeLook:
    """Return the pig's eye: a round, slightly oval pupil in a brown,
    light brown or dark chocolate iris; a few white pigs have blue-gray.

    Args:
        t: The individual. Its coat seed picks the iris.

    Returns:
        The look.
    """
    var s = Float64(Int(t.get("coatSeed", 0.0)) % 100) / 100.0
    var v = t.variant
    var pink_breed = v == LARGEWHITE or v == LANDRACE or v == SPOTTED
    var inner = 0x3A2214
    var mid = 0x6A4026
    var outer = 0x24140C
    var blue = s >= 0.95 and pink_breed
    if blue:
        inner = 0x4A5A66
        mid = 0x7A8C98
        outer = 0x2E3840
    elif s >= 0.75:
        inner = 0x1E120A
        mid = 0x321E12
        outer = 0x120A06
    elif s >= 0.5:
        inner = 0x4A2C16
        mid = 0x7C4C2A
        outer = 0x2E1A0C
    return EyeLook(
        srgb(inner), srgb(mid), srgb(outer), V3(0.6, 0.55, 0.52), 0.34, -1.15
    )


def _coat_hexes(variant: Int) -> List[Int]:
    # body, dorsal, belly, flush, ear, disc, hoof, bristle
    if variant == DUROC:
        return [
            0x9E6A58,
            0x94604F,
            0xA87462,
            0x9E6250,
            0x98604F,
            0xA87A6A,
            0x4A3A32,
            0xB87A48,
        ]
    var dark = variant == HAMPSHIRE or variant == BERKSHIRE
    if dark:
        return [
            0x504847,
            0x413A3A,
            0x524948,
            0x524544,
            0x4A3F3F,
            0x5A4E4E,
            0x3A3330,
            0x2C2727,
        ]
    return [
        0xF2D6CE,
        0xF4DDD6,
        0xF0CDC5,
        0xEAB2AA,
        0xEEC2BA,
        0xE4ACA6,
        0xC8AB98,
        0xF2ECE2,
    ]


def _spot_proxy(q: V3) -> V3:
    # A point projected onto a proxy of the barrel: an elliptic tube
    # round the body's axis.
    var cy = 0.53
    var d = V3(q.x, q.y - cy, 0.0)
    var l = length(d)
    var dd = d * (1.0 / l) if l > 1e-6 else V3(1.0, 0.0, 0.0)
    var e = sqrt((dd.x / 0.2) ** 2 + (dd.y / 0.2) ** 2)
    return V3(dd.x / e, cy + dd.y / e, q.z)


def _clear_of_joints(p: V3, r: Float64) -> Bool:
    # Off the limb junctions, whose skin stretches most.
    for s in [1.0, -1.0]:
        var st = V3(0.065 * s, 0.66, 0.255)
        var el = V3(0.1 * s, 0.31, 0.29)
        var hp = V3(0.09 * s, 0.55, -0.4)
        var kn = V3(0.11 * s, 0.36, -0.27)
        if segment_distance(p, st, el) < r + 0.1:
            return False
        if segment_distance(p, el, el + V3(0, 0.05, -0.16)) < r + 0.07:
            return False
        if segment_distance(p, hp, kn) < r + 0.07:
            return False
        if length(p - kn) < r + 0.12:
            return False
    return True


def pig_palette(t: Traits) raises -> Palette:
    """Return one pig's palette: its breed's skin, shaded, and the spotted
    pig's seeded spots.

    The spots ride in the palette: each lobe a center (`spot`) and a
    radius (`spotr`).

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.

    Raises:
        Error: Never; the signature matches the other species.
    """
    var hexes = _coat_hexes(t.variant)
    var names: List[String] = [
        String("body"),
        "dorsal",
        "belly",
        "flush",
        "ear",
        "disc",
        "hoof",
        "bristle",
    ]
    var k = t.get("coatShade", 0.0)
    var l = t.get("coatLightness", 0.0)
    var out = Palette()
    for i in range(len(names)):
        var c = srgb(hexes[i])
        out.set(
            names[i],
            V3(
                c.x * (1.0 + 0.06 * k + l),
                c.y * (1.0 + l),
                c.z * (1.0 - 0.05 * k + l),
            ),
        )
    out.set("white", srgb(0xE8D6CC))
    out.set("spot", srgb(0x3A3436))
    var R = AnimalRandom(7717 + Int(t.get("coatSeed", 0.0)), 1, 0)
    var off = V3(R.next() * 100.0, R.next() * 100.0, R.next() * 100.0)
    out.set("off", off)
    var count = 0
    if t.variant == SPOTTED:
        var n_spots = Int(t.get("spotCount", 8.0))
        var placed = List[V3]()
        var radii = List[Float64]()
        var i = 0
        while i < 400 and len(placed) < n_spots:
            i += 1
            var q = V3(
                (R.next() - 0.5) * 0.5,
                0.3 + 0.55 * R.next(),
                -0.62 + 1.3 * R.next(),
            )
            var rr = R.next()
            var nl = 1 + Int(R.next() * 2.2)
            var ls = List[Float64]()
            for _ in range(12):
                ls.append(R.next())
            var on_body = q.z < 0.32 and q.z > -0.6
            if not on_body:
                continue
            var p = _spot_proxy(q)
            if p.y < 0.4:
                continue
            var r = (0.045 + 0.07 * rr) * t.get("spotSize", 1.0)
            if not _clear_of_joints(p, 1.3 * r):
                continue
            var crowded = False
            for j in range(len(placed)):
                if length(p - placed[j]) < (r + radii[j]) * 1.15:
                    crowded = True
            if crowded:
                continue
            placed.append(p)
            radii.append(r)
            out.set("spot" + String(count), p)
            out.set("spotr" + String(count), V3(r, 0, 0))
            count += 1
            for j in range(nl):
                var d = V3(
                    ls[j * 4] - 0.5, ls[j * 4 + 1] - 0.5, ls[j * 4 + 2] - 0.5
                )
                var dl = length(d)
                dl = dl if dl > 0.0 else 1.0
                out.set("spot" + String(count), p + d * (0.55 * r / dl))
                out.set(
                    "spotr" + String(count),
                    V3(r * (0.45 + 0.3 * ls[j * 4 + 3]), 0, 0),
                )
                count += 1
    out.set("spots", V3(Float64(count), 0, 0))
    # The ears' frames, for the veins on their backs.
    var eb = _hl(EAR_BASE)
    var tip = _ear_spine(eb, 1.0, t).tip
    out.set("earBase", eb)
    out.set("earTip", tip)
    return out^


def _rag(p: V3, off: V3, f: Float64, a: Float64) -> Float64:
    return (fbm3(p * f + off, 2) - 0.5) * a


def _ear_vein_sd(u: Float64, w: Float64, seed: Int) -> Float64:
    # Signed distance, in leaf units, to the nearest vein on the back of
    # an ear leaf: a central vein and two marginal ones with branches.
    var veins: List[Float64] = [
        0.04, 0.0, 0.5, 0.02, 0.009, 0.006,
        0.5, 0.02, 0.88, 0.0, 0.006, 0.0025,
        0.06, 0.05, 0.42, 0.17, 0.008, 0.0055,
        0.42, 0.17, 0.8, 0.22, 0.0055, 0.0025,
        0.06, -0.05, 0.4, -0.15, 0.008, 0.0055,
        0.4, -0.15, 0.78, -0.2, 0.0055, 0.0025,
        0.28, 0.12, 0.5, 0.29, 0.004, 0.002,
        0.55, 0.19, 0.7, 0.31, 0.0035, 0.0018,
        0.3, -0.12, 0.52, -0.27, 0.004, 0.002,
        0.6, -0.18, 0.72, -0.29, 0.0035, 0.0018,
        0.62, 0.015, 0.8, 0.11, 0.003, 0.0016,
        0.66, 0.01, 0.82, -0.1, 0.003, 0.0016,
    ]  # fmt: skip
    var j = (Float64(seed % 13) / 13.0 - 0.5) * 0.04
    var d = 1.0
    for i in range(len(veins) // 6):
        var u0 = veins[6 * i]
        var w0 = veins[6 * i + 1] * (1.0 + j * 3.0)
        var u1 = veins[6 * i + 2]
        var w1 = veins[6 * i + 3] * (1.0 + j * 3.0) + j
        var dx = u1 - u0
        var dy = w1 - w0
        var tt = clamp(
            ((u - u0) * dx + (w - w0) * dy) / (dx * dx + dy * dy), 0.0, 1.0
        )
        var dd = sqrt((u - u0 - dx * tt) ** 2 + (w - w0 - dy * tt) ** 2)
        var r0 = veins[6 * i + 4]
        var r1 = veins[6 * i + 5]
        d = min(d, dd - 0.8 * (r0 + (r1 - r0) * tt))
    return d


def pig_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a pig.

    Bare skin per breed: pink with flushed ears, snout and belly in the
    white breeds, golden red in the Duroc, charcoal in the Hampshire with
    its white belt and in the Berkshire with its six white points, pink
    with seeded slate spots in the spotted pig. The moist rostral disc
    with dark nostrils, pink lid rims, veins on the backs of pink ears,
    skin creases on the neck, the snout and the legs, pale or dark claws,
    ivory tusks, and seeded mud on the feet.

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
    var v = t.variant
    var dark = v == HAMPSHIRE or v == BERKSHIRE
    var pink = v == LARGEWHITE or v == LANDRACE or v == SPOTTED
    var piglet = t.juvenile() > 0.0
    var f = _frame()
    var h = f.local(p)
    var off = pal.get("off")
    var up = clamp(n.y, -1.0, 1.0)
    var snout_k = t.get("snoutLen", 1.0) * SNOUT_K
    var dz = 0.06 + (0.178 - 0.06) * snout_k
    var disc_w = smoothstep(dz - 0.02, dz - 0.002, h.z)
    if s.part == TEETH:
        var cones = _tusk_cones(t, 1.0 if p.x >= 0.0 else -1.0)
        var root = cones[0]
        var tip = cones[len(cones) - 2]
        var u = clamp(
            1.0 - length(p - tip) / max(1e-4, length(root - tip)), 0.0, 1.0
        )
        return Paint(
            mix3(srgb(0xECE2CC), srgb(0xFBF6EC), smoothstep(0.25, 0.85, u)),
            KERATIN,
        )
    var region = 0
    if s.part == JAW:
        region = 6
    elif s.part == EAR:
        region = 5
    elif s.part == TAIL:
        region = 4
    else:
        var snout = (
            bone == "snout"
            or tag == "disc"
            or tag == "snoutend"
            or tag == "nostril"
        )
        if snout:
            region = 7
        elif bone == "head":
            region = 2
        elif bone == "neck1" or bone == "neck2":
            region = 1
    var legness = 0.0
    if is_limb(bone):
        var upper = (
            bone.startswith("scapula")
            or bone.startswith("humerus")
            or bone.startswith("femur")
        )
        legness = smoothstep(0.45, 0.3, p.y) if upper else 1.0
    var ventral = 0.0
    var low_part = region <= 2 or region == 6
    if low_part:
        ventral = smoothstep(-0.2, -0.8, n.y) * smoothstep(0.55, 0.35, p.y)
    var skin = mix3(
        mix3(
            pal.get("body"), pal.get("dorsal"), smoothstep(0.3, 0.95, up) * 0.7
        ),
        pal.get("belly"),
        ventral,
    )
    var c = skin
    if region <= 1:
        if legness > 0.0 and pink:
            c = mix3(
                c, pal.get("flush"), 0.25 * smoothstep(0.3, 0.1, p.y) * legness
            )
        var hoofish = tag == "hoof" or tag == "heelbulb" or tag == "dewclaw"
        if hoofish:
            var cz = 0.345 if bone.startswith("f") else -0.338
            var below = p.y < 0.028 + 0.009 + 0.3 * (p.z - cz)
            if tag == "dewclaw" or below:
                var streak = smoothstep(
                    0.45,
                    0.65,
                    fbm3(
                        V3(
                            p.x * 140.0
                            + Float64(Int(t.get("coatSeed", 0.0)) % 97),
                            p.y * 9.0,
                            p.z * 140.0,
                        ),
                        2,
                    ),
                )
                var hc = pal.get("hoof")
                hc = mix3(hc, hc * 0.55, 0.35 * streak) if pink else mix3(
                    hc, hc * 1.5, 0.3 * streak
                )
                if tag == "heelbulb":
                    hc = mix3(hc, srgb(0xC89C8A) if pink else hc * 0.8, 0.5)
                hc = _mud(t, hc, p, off)
                return Paint(hc, KERATIN)
        if tag == "teat":
            c = srgb(0xD49A8E) if pink else mix3(
                pal.get("body"), srgb(0x6A5050), 0.3
            )
        var gen = tag == "scrotum" or tag == "sheath"
        if gen:
            c = mix3(c, pal.get("flush"), 0.35 if pink else 0.1)
    elif region == 4:
        c = mix3(pal.get("body"), pal.get("dorsal"), 0.4)
        if pink:
            c = mix3(c, pal.get("flush"), 0.15)
    elif region == 5:
        # The ear: thin skin, the hollow side redder toward its root.
        var eb = pal.get("earBase")
        var tip = pal.get("earTip")
        var sd = 1.0 if p.x >= 0.0 else -1.0
        eb = V3(eb.x * sd, eb.y, eb.z)
        tip = V3(tip.x * sd, tip.y, tip.z)
        var ev = tip - eb
        var se = clamp(dot(p - eb, ev) / dot(ev, ev), 0.0, 1.0)
        var kin = smoothstep(-0.0015, 0.0015, s.local.z)
        var in_col = mix3(
            srgb(0xE8A098), srgb(0xF2BCB2), smoothstep(0.08, 0.55, se)
        ) if pink else mix3(pal.get("ear"), pal.get("flush"), 0.1) * (
            1.0 if dark else 1.06
        )
        var out_col = mix3(pal.get("ear"), pal.get("body"), 0.5)
        c = mix3(out_col, in_col, kin)
        if pink and kin < 0.2:
            # Veins on the back of the leaf, from the root toward the tip.
            var le = length(ev)
            var evn = ev * (1.0 / le)
            var face = normalize(V3(s.n.x, s.n.y, s.n.z))
            var lat = normalize(cross(evn, face))
            var q = p - eb
            var u = dot(q, evn) / le
            var w = dot(q, lat) / le + 0.008 * (fbm3(p * 35.0 + off, 2) - 0.5)
            var vsd = _ear_vein_sd(u, w * sd, Int(t.get("coatSeed", 0.0))) * le
            var vein = smoothstep(0.0006, -0.0006, vsd)
            c = mix3(c, V3(c.x * 0.9, c.y * 0.74, c.z * 0.78), vein)
    elif region == 7:
        # The rostral disc: moist and glossy, with dark nostrils.
        var face = disc_w * smoothstep(0.2, 0.6, dot(n, f.hz))
        var snout_col = mix3(skin, pal.get("flush"), 0.25) if pink else skin
        var disc = mix3(
            pal.get("disc"), pal.get("flush") if pink else pal.get("disc"), 0.2
        )
        c = mix3(snout_col, disc, disc_w)
        if tag == "nostril":
            var depth = dz + 0.012 - h.z
            var deep = smoothstep(0.002, 0.014, depth)
            var nc = mix3(
                pal.get("disc") * 0.4 if dark else srgb(0x5A3230),
                srgb(0x140A0A) if dark else srgb(0x2A1214),
                deep,
            )
            return Paint(nc, SKIN)
        # The pitted face of the plate.
        var pits = smoothstep(0.55, 0.8, vnoise3(p * 900.0))
        c = c * (1.0 - 0.12 * pits * face)
        if v == BERKSHIRE:
            c = mix3(pal.get("white"), srgb(0xE2B4AA), 0.7 * disc_w)
    else:
        # The head and the jaw.
        c = skin
        if pink:
            c = mix3(c, pal.get("flush"), 0.25 * smoothstep(0.06, 0.17, h.z))
        if region == 2:
            var disc = mix3(
                pal.get("disc"),
                pal.get("flush") if pink else pal.get("disc"),
                0.2,
            )
            c = mix3(c, disc, disc_w)
        if tag == "tongue":
            var tc = srgb(0xC47A72)
            return Paint(
                mix3(tc, tc * 0.75, smoothstep(0.03, 0.1, -h.z + 0.12)), SKIN
            )
        # The lid rims: pink or dark lid skin.
        var e = pig_eye(t)
        var ef = eye_frame_of(e, HEAD_O, 1.0 if p.x >= 0.0 else -1.0)
        var near_eye = length(p - ef.c) < 0.03
        if near_eye:
            var de = lid_distance(e, ef, p)
            if pink and de < 0.014:
                c = mix3(
                    c,
                    pal.get("flush"),
                    0.42 * (1.0 - smoothstep(0.003, 0.014, de)),
                )
            if de < 0.003:
                c = pal.get("body") * 0.6 if dark else mix3(
                    c,
                    pal.get("flush"),
                    0.55 * (1.0 - smoothstep(0.002, 0.003, de)) + 0.25,
                )
            elif de < 0.0115:
                var up_amt = dot(p - ef.c, ef.y) / 0.011
                var xr = abs(dot(p - ef.c, ef.x))
                var along = smoothstep(0.0125, 0.006, xr)
                var fold = (
                    exp(-(((de - 0.0045) / 0.0011) ** 2)) * 0.2 if up_amt
                    > 0.0 else exp(-(((de - 0.0036) / 0.0009) ** 2)) * 0.1
                )
                c = c * (1.0 - fold * along)
                var lash = not dark and up_amt > 0.2
                if lash:
                    c = mix3(
                        c,
                        srgb(0xF6EFE6),
                        0.45
                        * smoothstep(0.2, 0.5, up_amt)
                        * (1.0 - smoothstep(0.0032, 0.0048, de)),
                    )
        # The mouth line: a fine crease where the upper lip overhangs.
        var lip_line = (
            region == 2
            and h.z > 0.045
            and h.y < -0.06
            and h.y > -0.075
            and n.y < 0.3
        )
        if lip_line:
            var zk = smoothstep(0.045, 0.065, h.z)
            c = mix3(c, srgb(0x9A5552) * 0.7, 0.5 * zk)
    # Creases: across the neck behind the jowls, over the snout and the
    # legs; deeper in older pigs.
    var wr = 0.6 + 0.6 * t.get("wrinkles", 0.5)
    var crease = 0.0
    if not piglet:
        if region == 1:
            var nb = V3(0.0, 0.56, 0.33)
            var occ = _hl(V3(0.0, -0.015, -0.115))
            var ax = occ - nb
            var sn = (
                1.0 - clamp(dot(p - nb, ax) / dot(ax, ax), 0.0, 1.0)
            ) * length(ax)
            var ph = (sn + 0.012 * (fbm3(p * 25.0 + off, 2) - 0.5)) / 0.03
            var fr = abs(ph - floor(ph + 0.5))
            crease = (
                exp(-(((fr * 0.03) / 0.0045) ** 2))
                * smoothstep(0.015, 0.035, sn)
                * smoothstep(0.13, 0.08, sn)
                * smoothstep(0.5, -0.1, n.y)
                * 0.55
                * wr
            )
        var snout_top = region == 2 or (region == 7 and tag != "nostril")
        if snout_top:
            var ddz = dz - h.z + 6.0 * h.x * h.x
            var ph = (ddz + 0.003 * (fbm3(p * 40.0 + off, 2) - 0.5)) / 0.0095
            var fr = abs(ph - floor(ph + 0.5))
            crease = (
                exp(-(((fr * 0.0095) / 0.0018) ** 2))
                * smoothstep(0.015, 0.025, ddz)
                * smoothstep(0.065, 0.04, ddz)
                * smoothstep(0.15, 0.55, dot(n, f.hy))
                * 0.5
                * wr
            )
        if legness > 0.5:
            var jy = 0.15 if is_front_limb(bone) else 0.17
            var dy = p.y - jy
            var ph = abs(dy / 0.012 - floor(dy / 0.012))
            crease = max(
                crease,
                smoothstep(0.2, 0.0, min(ph, 1.0 - ph))
                * smoothstep(0.03, 0.01, abs(dy))
                * 0.7
                * t.get("wrinkles", 0.5),
            )
    c = c * (1.0 - 0.28 * min(1.0, crease))
    # The breed's markings.
    c = _markings(pal, t, region, tag, bone, legness, h, p, c, off)
    # The bristles: a faint pale haze on pink skin, golden on the Duroc,
    # black on the dark breeds.
    var bristle = pal.get("bristle")
    var haze = 0.06 * smoothstep(0.55, 0.85, vnoise3(p * 700.0))
    c = mix3(c, bristle, haze)
    # A faint, broad warm variation of the skin.
    var cv = fbm3(p * 3.0 + V3(off.z, 0.0, 0.0), 2) - 0.5
    if region != 7:
        c = V3(
            c.x * (1.0 + 0.035 * cv),
            c.y * (1.0 + 0.012 * cv),
            c.z * (1.0 + 0.012 * cv),
        )
    var muddy = region <= 1
    if muddy:
        c = _mud(t, c, p, off)
    return Paint(c, SKIN)


def _mud(t: Traits, c: V3, p: V3, off: V3) -> V3:
    # Mud caked on the hooves and the pasterns, dry pale gray or wet.
    var mud = t.get("mud", 0.0)
    if mud <= 0.0:
        return c
    var caked = smoothstep(
        0.075, 0.035, p.y + 0.02 * (fbm3(p * 9.0 + off + V3(3, 0, -3), 3) - 0.5)
    )
    var mk = clamp(caked * min(1.0, 1.6 * mud), 0.0, 0.85)
    var mc = mix3(
        srgb(0x857060),
        srgb(0xA89C8C),
        smoothstep(0.4, 0.65, fbm3(p * 5.0 + off + V3(9, 0, -9), 3)),
    )
    return mix3(c, mc, mk)


def _markings(
    pal: Palette,
    t: Traits,
    region: Int,
    tag: String,
    bone: String,
    legness: Float64,
    h: V3,
    p: V3,
    c: V3,
    off: V3,
) -> V3:
    var v = t.variant
    if v == SPOTTED:
        var none = region == 7 or region == 6 or region == 5 or tag == "teat"
        var snout = region == 2 and h.z >= 0.06
        if none or snout:
            return c
        var d = 1.0
        var count = Int(pal.get("spots").x)
        for i in range(count):
            var q = pal.get("spot" + String(i))
            d = min(d, length(p - q) - pal.get("spotr" + String(i)).x)
        d += _rag(p, off, 12.0, 0.06) + _rag(p, off, 45.0, 0.012)
        return mix3(c, pal.get("spot"), smoothstep(0.011, -0.011, d))
    if v == HAMPSHIRE:
        var none = region == 7 or region == 6 or region == 5 or region == 4
        if none:
            return c
        var d: Float64
        var front_leg = is_front_limb(bone) and legness > 0.4
        if front_leg:
            d = -0.03
        else:
            var zb = t.get("beltBack", 0.02) + 0.05 * (p.y - 0.45)
            var cap = min(h.y - 0.025, h.z + 0.115)
            var head_side = region == 2 or region == 1
            var hz = h.z if head_side else -1.0
            d = max(max(hz - t.get("beltFront", -0.055), cap), zb - p.z)
            d += _rag(p, off, 18.0, 0.03)
        return mix3(c, pal.get("white"), smoothstep(0.011, -0.011, d))
    if v == BERKSHIRE:
        var d = 1.0
        if region == 7:
            d = -0.02
        elif region == 2 or region == 6:
            var w = 0.012 + 0.03 * smoothstep(0.05, 0.16, h.z) * t.get(
                "blaze", 1.0
            )
            var snout_edge = 0.08 + 0.5 * max(0.0, -0.03 - h.y)
            var blaze = 1.0 if region == 6 else abs(h.x) - w
            d = min(blaze, snout_edge - h.z) + _rag(p, off, 30.0, 0.012)
        elif region == 4:
            var ab = V3(0.0, 0.69, -0.59)
            var tail_t = clamp(length(p - ab) / 0.16, 0.0, 1.0)
            d = (0.55 - tail_t) * 0.05 + _rag(p, off, 40.0, 0.004)
        elif legness > 0.2:
            var top = 0.13 if is_front_limb(bone) else 0.14
            d = p.y - top * t.get("socks", 1.0) + _rag(p, off, 25.0, 0.03)
        return mix3(c, pal.get("white"), smoothstep(0.004, -0.004, d))
    return c
