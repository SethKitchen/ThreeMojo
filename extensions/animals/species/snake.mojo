# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The snake: procedural-animals' `species/snake/`.

Two builds share the code. The corn snake, Pantherophis guttatus, is the
default: 1.2 m long, with a narrow head and red saddles edged in black on
an orange ground. The western diamondback rattlesnake, Crotalus atrox,
has a broad triangular head, dark diamonds with pale edges, a ringed
"coon tail" and a rattle.

The snake lies straight along -z with its belly on y = 0 and its head
at +z. The body is a chain of round cones on 50 spine bones, and a very
flat carving ellipsoid cuts the flat belly.
"""

from extensions.animals.coat import (
    KERATIN,
    SCALES,
    SKIN,
    WET,
    CoatSample,
    EyeLook,
    Paint,
    Palette,
    mix3,
    srgb,
)
from extensions.animals.parts import (
    APPENDAGE,
    JAW,
    TEETH,
    TONGUE,
)
from extensions.animals.kit import (
    EyeSpec,
    eye_frame_of,
    sculpt_eye_socket,
)
from extensions.animals.noise import fbm3, ihash
from extensions.animals.options import AnimalOptions, AnimalRandom
from extensions.animals.rig import Rig
from extensions.sdf.field import SdfModel
from extensions.animals.traits import Traits, pick_age, pick_sex
from extensions.sdf.vector import (
    V3,
    clamp,
    length,
    lerp,
    normalize,
    smoothstep,
)
from std.math import atan2, floor, sin, sqrt
from extensions.sdf.distance import rect_distance

# Spine bones, each about four or five vertebrae.
comptime SPINE = 50
# The head's origin: the reference corn snake's occiput, `v0`. An
# individual's occiput sits a little higher or lower with its girth, and
# its eye moves with it.
comptime HEAD_O = V3(0.0, 0.0071 * 0.74, 0.0)
# The finest cell, at the `HERO` tier: the corn snake's head cell.
comptime CELL = 0.00048

# The builds, in procedural-animals' order.
comptime CORN = 0
comptime RATTLESNAKE = 1

# The corn snake's morphs, in procedural-animals' order.
comptime NORMAL = 0
comptime OKEETEE = 1
comptime WILD = 2
comptime AMEL = 3
comptime ANERY = 4

# The rattle: its length and its segment count in the reference adult.
comptime RATTLE_LEN = 0.05
comptime RATTLE_SEGS = 7


def snake_variant_names() -> List[String]:
    """Return the snake's builds.

    Returns:
        Corn snake and western diamondback rattlesnake.
    """
    return [String("corn"), "rattlesnake"]


def snake_traits(mut r: AnimalRandom, options: AnimalOptions) raises -> Traits:
    """Draw one snake: procedural-animals' `variation`.

    Males are larger with longer tails. Hatchlings are about 0.3 m long,
    with relatively bigger heads and eyes. The build is never drawn: a
    snake is a corn snake unless the caller asks for the rattlesnake.

    Args:
        r: The individual's stream.
        options: The caller's sex, age and build.

    Returns:
        The traits.

    Raises:
        Error: If the requested build is not one of the two.
    """
    if options.variant.value >= 2:
        raise Error("The snake has no such color variant")
    var variant = RATTLESNAKE if options.variant.value == RATTLESNAKE else CORN
    var viper = variant == RATTLESNAKE
    var sex = pick_sex(options.sex, r)
    var age = pick_age(options.age)
    var t = Traits(sex, age, variant)
    var juv = t.juvenile() > 0.0
    var male = t.male()
    var viper_male = viper and male
    var viper_female = viper and not male
    var size = (
        (1.04 if male else 0.96)
        * (1.0 + 0.1 * r.g())
        * (0.27 if juv else 1.0)
        * (1.05 if viper_male else 1.0)
    )
    t.set("size", size)
    t.set(
        "girth",
        (1.0 + 0.07 * r.g())
        * (0.92 if juv else 1.0)
        * (1.04 if viper_female else 1.0),
    )
    t.set("head", (1.0 + 0.04 * r.g()) * (1.4 if juv else 1.0))
    t.set("tail", (1.08 if male else 0.94) * (1.0 + 0.04 * r.g()))
    var m = r.next()
    var morph = NORMAL if m < 0.52 else (
        OKEETEE if m
        < 0.68 else (WILD if m < 0.84 else (AMEL if m < 0.94 else ANERY))
    )
    t.set("morph", Float64(morph))
    t.set("minThick", 0.0005)
    var segs = 0.0
    if viper:
        segs = 1.0 if juv else 5.0 + floor(r.next() * 4.0)
    t.set("rattleSegs", segs)
    t.set("coatSeed", Float64(Int(r.next() * 1e6)))
    t.set("coatWarm", 1.1 * r.g())
    t.set("coatLight", 0.1 * r.g())
    t.set("count", 1.0 + 0.1 * r.g())
    t.set("dull", max(0.0, 0.45 * r.g() + 0.1))
    t.set("blotch", 1.0 + 0.18 * r.g())
    var tone = 0.0
    if viper:
        tone = 2.0 * r.next() - 1.0
    t.set("tone", tone)
    t.set("res", options.quality.resolution())
    return t^


struct _Plan(Movable):
    """One individual's body plan: procedural-animals' `bodyPlan`."""

    var viper: Bool
    var head_len: Float64
    var body_len: Float64
    var tail_frac: Float64
    var ref_tail: Float64
    var flat: Float64
    var kh: Float64
    var kg: Float64
    var head_w: Float64
    var head_h: Float64
    var xs: List[Float64]
    var ys: List[Float64]
    var ms: List[Float64]

    def __init__(out self, t: Traits):
        self.viper = t.variant == RATTLESNAKE
        var tl = 1.2
        var p_head = 0.052 if self.viper else 0.034
        var p_tail = 0.075 if self.viper else 0.17
        self.head_w = 0.038 if self.viper else 0.0185
        self.head_h = 0.02 if self.viper else 0.0112
        self.flat = 0.64 if self.viper else 0.74
        self.kg = t.get("girth")
        self.kh = t.get("head")
        var kt = t.get("tail")
        self.head_len = p_head * self.kh
        self.body_len = tl - self.head_len
        self.tail_frac = min(0.3, (p_tail * kt * tl) / self.body_len)
        self.ref_tail = (p_tail * tl) / (tl - p_head)
        if self.viper:
            self.xs = [0.0, 0.04, 0.2, 0.46, 0.7, 0.86, 0.92, 0.97, 1.0]
            self.ys = [
                0.0092,
                0.0105,
                0.019,
                0.0265,
                0.0238,
                0.016,
                0.0112,
                0.0078,
                0.0062,
            ]
        else:
            self.xs = [0.0, 0.05, 0.22, 0.45, 0.66, 0.8, 0.88, 0.95, 1.0]
            self.ys = [
                0.0071,
                0.0076,
                0.0112,
                0.0135,
                0.0128,
                0.0098,
                0.0068,
                0.0036,
                0.0011,
            ]
        self.ms = _pchip_slopes(self.xs, self.ys)

    def hw(self, t: Float64) -> Float64:
        """The body's half width at arc fraction `t` from the occiput."""
        var tf = self.tail_frac
        var u = (t / (1.0 - tf)) * (
            1.0 - self.ref_tail
        ) if t <= 1.0 - tf else 1.0 - self.ref_tail + (
            (t - (1.0 - tf)) / tf
        ) * self.ref_tail
        var r = _pchip(self.xs, self.ys, self.ms, u)
        var neck = 1.0 - min(1.0, t / 0.1)
        return r * (
            self.kg * (1.0 - neck) + (0.5 * self.kg + 0.5 * self.kh) * neck
        )

    def height(self) -> Float64:
        """The occiput's height above the belly plane."""
        return self.hw(0.0) * self.flat


def _pchip_slopes(x: List[Float64], y: List[Float64]) -> List[Float64]:
    # Fritsch-Carlson slopes of a monotone cubic.
    var n = len(x)
    # A curve of fewer than two points has no slope.
    if n < 2 or len(y) != n:
        return List[Float64](length=n, fill=0.0)
    var d = List[Float64]()
    # Two points at least, checked above: `d[0]` and `d[n - 2]` are read
    # below.
    for i in range(n - 1):  # pragma: no branch
        d.append((y[i + 1] - y[i]) / (x[i + 1] - x[i]))
    var m = List[Float64](length=n, fill=0.0)
    m[0] = d[0]
    m[n - 1] = d[n - 2]
    for i in range(1, n - 1):
        m[i] = 0.0 if d[i - 1] * d[i] <= 0.0 else (d[i - 1] + d[i]) / 2.0
    for i in range(n - 1):  # pragma: no branch
        if d[i] == 0.0:
            m[i] = 0.0
            m[i + 1] = 0.0
            continue
        var a = m[i] / d[i]
        var b = m[i + 1] / d[i]
        var s = a * a + b * b
        if s > 9.0:
            var k = 3.0 / sqrt(s)
            m[i] = k * a * d[i]
            m[i + 1] = k * b * d[i]
    return m^


def _pchip(
    x: List[Float64], y: List[Float64], m: List[Float64], t: Float64
) -> Float64:
    var n = len(x)
    if t <= x[0]:
        return y[0]
    if t >= x[n - 1]:
        return y[n - 1]
    var i = 0
    while i < n - 2 and t > x[i + 1]:
        i += 1
    var h = x[i + 1] - x[i]
    var u = (t - x[i]) / h
    var u2 = u * u
    var u3 = u2 * u
    var h00 = 2.0 * u3 - 3.0 * u2 + 1.0
    var h10 = u3 - 2.0 * u2 + u
    var h01 = -2.0 * u3 + 3.0 * u2
    var h11 = u3 - u2
    return h00 * y[i] + h10 * h * m[i] + h01 * y[i + 1] + h11 * h * m[i + 1]


def _segments(n: Int, total: Float64, tip_shrink: Float64) -> List[Float64]:
    # procedural-animals' `snakeSegments`: uniform bones, shorter toward
    # the tail tip so the thin tail can curl, and at the neck.
    var tip_bones = 10
    var neck_bones = 3
    var w = List[Float64]()
    var sw = 0.0
    # Its one caller asks for `SPINE` bones.
    for i in range(n):
        var k = 1.0
        if i >= n - tip_bones:
            k = 1.0 - (1.0 - tip_shrink) * (
                Float64(i - (n - tip_bones) + 1) / Float64(tip_bones)
            )
        if i < neck_bones:
            k = 0.85 + 0.15 * (Float64(i) / Float64(neck_bones))
        w.append(k)
        sw += k
    var out = List[Float64]()
    for k in w:
        out.append(k * total / sw)
    return out^


def snake_rig(t: Traits) raises -> Rig:
    """Return the snake's skeleton in bind pose.

    The spine runs from the occiput `v0` back to the tail tip `v50`, each
    joint on the body's axis at its height above the belly. The head, the
    jaw, the tongue and the fangs hang from the first spine bone.

    Args:
        t: The individual.

    Returns:
        The rig.

    Raises:
        Error: If a bone names a missing joint.
    """
    var plan = _Plan(t)
    var lens = _segments(SPINE, plan.body_len, 0.8 if plan.viper else 0.5)
    var rig = Rig()
    var total = plan.body_len
    var s = 0.0
    var prev = V3(0.0, plan.height(), 0.0)
    rig.set("v0", prev)
    var z = 0.0
    for i in range(SPINE):  # pragma: no branch
        s += lens[i]
        var y = plan.hw(s / total) * plan.flat
        var dy = y - prev.y
        z -= sqrt(max(1e-10, lens[i] * lens[i] - dy * dy))
        prev = V3(0.0, y, z)
        rig.set("v" + String(i + 1), prev)
    var hl = plan.head_len
    var hh = plan.head_h * plan.kh
    rig.set("nose", V3(0.0, 0.56 * hh, hl))
    rig.set("jawHinge", V3(0.0, 0.34 * hh, 0.06 * hl))
    rig.set("jawTip", V3(0.0, 0.16 * hh, 0.9 * hl))
    rig.set("tongueBase", V3(0.0, 0.2 * hh, 0.18 * hl))
    rig.set("tongueFork", V3(0.0, 0.2 * hh, 0.62 * hl))
    rig.set("tongueTip", V3(0.0, 0.2 * hh, 0.84 * hl))
    rig.set("fangBase", V3(0.0, 0.38 * hh, 0.72 * hl))
    rig.set("fangTip", V3(0.0, 0.32 * hh, 0.55 * hl))
    for i in range(SPINE):  # pragma: no branch
        _ = rig.add_bone(
            "spine" + String(i),
            "v" + String(i),
            "v" + String(i + 1),
            "" if i == 0 else "spine" + String(i - 1),
        )
    _ = rig.add_bone("head", "v0", "nose", "spine0")
    _ = rig.add_bone("jaw", "jawHinge", "jawTip", "head")
    _ = rig.add_bone("tongue", "tongueBase", "tongueFork", "jaw")
    _ = rig.add_bone("tongueTip", "tongueFork", "tongueTip", "tongue")
    _ = rig.add_bone("fang", "fangBase", "fangTip", "head")
    return rig^


def _eye_at(plan: _Plan) -> V3:
    # The eye's center from the occiput, head-local.
    var k = plan.kh
    if plan.viper:
        return V3(0.0133 * k, 0.0052 * k, 0.032 * k)
    return V3(0.006 * k, 0.0027 * k, 0.0205 * k)


def snake_eye(t: Traits) -> EyeSpec:
    """Return the snake's left eye: no lids, a round spectacle.

    The iris fills the whole visible eye. A hatchling's eye is larger.

    Args:
        t: The individual.

    Returns:
        The eye, from `HEAD_O`.
    """
    var plan = _Plan(t)
    var k = plan.kh * (1.15 if t.juvenile() > 0.0 else 1.0)
    var r = (0.0029 if plan.viper else 0.0026) * k
    var at = _eye_at(plan)
    # The pipeline places the eye from `HEAD_O`: shift it to this
    # individual's occiput.
    var c = V3(at.x, at.y + plan.height() - HEAD_O.y, at.z)
    return EyeSpec(
        c,
        r,
        0.0002 * plan.kh,
        1.0 if plan.viper else 1.05,
        0.22 if plan.viper else 0.2,
        0.00015 * plan.kh,
        r * 0.96,
        0.0,
        0.0,
        0.0,
        r * 0.62,
        r * 0.9,
    )


def snake_sculpt(mut m: SdfModel, rig: Rig, t: Traits) raises:
    """Sculpt the snake: procedural-animals' `sculptSnake`, primitive for
    primitive.

    The body is a tube of round cones whose radius is the half width. The
    axis sits at `flat` times the half width, so the belly plane cuts the
    circle's lower part off: a flat belly with angled sides. The head is
    modeled from the occiput. The lower jaw, the forked tongue, the fangs
    and the rattle are surfaces of their own.

    Args:
        m: The sculpt to add to.
        rig: The snake's rig in bind pose.
        t: The individual.

    Raises:
        Error: If the rig lacks a joint or a bone, or the sculpt refuses
            a primitive.
    """
    var plan = _Plan(t)
    var viper = plan.viper
    var ho = rig.j("v0")
    var hl = plan.head_len
    var w = plan.head_w * plan.kh
    var hh = plan.head_h * plan.kh
    var yb = -ho.y
    var hb = rig.bone("head")

    # BODY: round cones of radius the half width.
    var sig = List[Float64]()
    sig.append(0.0)
    var total = 0.0
    for i in range(SPINE):  # pragma: no branch
        total += length(rig.j("v" + String(i + 1)) - rig.j("v" + String(i)))
        sig.append(total)
    var hw_at = List[Float64]()
    for i in range(SPINE + 1):  # pragma: no branch
        hw_at.append(plan.hw(sig[i] / total))
    var tail_from = Float64(SPINE) * (1.0 - plan.tail_frac)
    for i in range(SPINE):  # pragma: no branch
        var tag = String("tail") if Float64(i) >= tail_from else (
            String("neck") if i < 3 else String("body")
        )
        _ = m.cone(
            tag,
            rig.bone("spine" + String(i)),
            rig.j("v" + String(i)),
            rig.j("v" + String(i + 1)),
            hw_at[i],
            hw_at[i + 1],
            k=0.0,
        )
    # The thin tail tip: overlapping ellipsoids the coarse tiers inflate.
    for i in range(SPINE - 12, SPINE):  # pragma: no branch
        var a = rig.j("v" + String(i))
        var b = rig.j("v" + String(i + 1))
        var rr = (hw_at[i] + hw_at[i + 1]) * 0.5
        _ = m.ell(
            "tailtip",
            rig.bone("spine" + String(i)),
            lerp(a, b, 0.5),
            V3(rr * 0.98, rr * 0.98, length(a - b) * 0.62),
            axis=normalize(a - b),
            k=0.0,
            thin=True,
        )

    # HEAD: the upper jaw and the braincase.
    var e = snake_eye(t)
    var at = _eye_at(plan)
    if viper:
        # Broad and triangular: venom-gland bulges at the back, a flat
        # crown, a blunt canthus and a narrow neck.
        _ = m.ell(
            "cranium",
            hb,
            ho + V3(0, yb + 0.62 * hh, 0.36 * hl),
            V3(0.33 * w, 0.34 * hh, 0.36 * hl),
            k=0.004,
        )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "gland",
                hb,
                ho + V3(0.31 * w * s, yb + 0.5 * hh, 0.22 * hl),
                V3(0.28 * w, 0.34 * hh, 0.27 * hl),
                axis=normalize(V3(0.35 * s, 0, 1)),
                k=0.005,
            )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "cheek",
                hb,
                ho + V3(0.2 * w * s, yb + 0.5 * hh, 0.52 * hl),
                V3(0.22 * w, 0.3 * hh, 0.3 * hl),
                axis=normalize(V3(-0.25 * s, 0, 1)),
                k=0.005,
            )
        _ = m.ell(
            "snout",
            hb,
            ho + V3(0, yb + 0.58 * hh, 0.7 * hl),
            V3(0.29 * w, 0.28 * hh, 0.25 * hl),
            k=0.005,
        )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "lip",
                hb,
                ho + V3(0.26 * w * s, yb + 0.38 * hh, 0.5 * hl),
                V3(0.16 * w, 0.16 * hh, 0.44 * hl),
                axis=normalize(V3(-0.28 * s, 0, 1)),
                k=0.004,
            )
        _ = m.sphere(
            "rostral",
            hb,
            ho + V3(0, yb + 0.5 * hh, 0.94 * hl),
            0.13 * w,
            k=0.004,
        )
        # The supraocular scales: a brow shelf over each eye.
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "brow",
                hb,
                ho + V3(at.x * s * 0.95, at.y + e.r * 0.95, at.z),
                V3(e.r * 1.25, e.r * 0.5, e.r * 1.5),
                k=0.0015,
            )
    else:
        # The corn snake: barely wider than the neck, a long rounded
        # snout and a domed crown.
        _ = m.ell(
            "cranium",
            hb,
            ho + V3(0, yb + 0.6 * hh, 0.34 * hl),
            V3(0.42 * w, 0.4 * hh, 0.4 * hl),
            k=0.004,
        )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "temporal",
                hb,
                ho + V3(0.2 * w * s, yb + 0.5 * hh, 0.2 * hl),
                V3(0.28 * w, 0.36 * hh, 0.3 * hl),
                k=0.004,
            )
        _ = m.ell(
            "snout",
            hb,
            ho + V3(0, yb + 0.56 * hh, 0.72 * hl),
            V3(0.29 * w, 0.34 * hh, 0.3 * hl),
            axis=normalize(V3(0, -0.08, 1)),
            k=0.005,
        )
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.ell(
                "lip",
                hb,
                ho + V3(0.24 * w * s, yb + 0.4 * hh, 0.52 * hl),
                V3(0.19 * w, 0.2 * hh, 0.42 * hl),
                axis=normalize(V3(-0.22 * s, 0, 1)),
                k=0.004,
            )
        _ = m.sphere(
            "rostral",
            hb,
            ho + V3(0, yb + 0.5 * hh, 0.92 * hl),
            0.17 * w,
            k=0.004,
        )
    # The neck: the cranium blends into the first body cone.
    _ = m.cone(
        "nape",
        hb,
        ho + V3(0, 0, 0.18 * hl),
        ho + V3(0, 0, -0.25 * hl),
        0.3 * w,
        hw_at[0] * 1.02,
        k=0.01,
    )
    # Eyes in round sockets (the spectacle sits flush), the nostrils, the
    # pits and the rostral notch the tongue slips through.
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = sculpt_eye_socket(
            m,
            e,
            HEAD_O,
            s,
            hb,
            orbit_r=V3(e.r * 0.95, e.r * 0.8, e.r * 0.45),
            orbit_at=V3(0, 0, e.r),
            orbit_k=e.r * 0.35,
        )
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.sphere(
            "nostril",
            hb,
            ho + V3(0.17 * w * s, yb + 0.62 * hh, 0.95 * hl),
            0.04 * w,
            k=0.0006,
            carve=True,
        )
    if viper:
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.sphere(
                "pit",
                hb,
                ho + V3(0.33 * w * s, yb + 0.48 * hh, 0.8 * hl),
                0.05 * w,
                k=0.0006,
                carve=True,
            )
    _ = m.ell(
        "notch",
        hb,
        ho + V3(0, yb + 0.36 * hh, 0.99 * hl),
        V3(0.07 * w, 0.07 * hh, 0.05 * hl),
        k=0.0006,
        carve=True,
    )
    # The palate: the upper jaw ends at the lip line.
    _ = m.ell(
        "palate",
        hb,
        ho + V3(0, yb + 0.1 * hh, 0.62 * hl),
        V3(0.33 * w, 0.26 * hh, 0.5 * hl),
        k=0.0012,
        carve=True,
    )
    # The belly plane: a very flat carving ellipsoid whose top is y = 0.
    var z_mid = (ho.z + rig.j("v" + String(SPINE)).z) * 0.5
    _ = m.ell(
        "belly",
        rig.bone("spine" + String(SPINE // 2)),
        V3(0, -0.012, z_mid),
        V3(0.4, 0.012, 3.2),
        k=0.18 * hw_at[SPINE // 2],
        carve=True,
    )

    # LOWER JAW: its own surface.
    var jw = rig.bone("jaw")
    for s in [1.0, -1.0]:  # pragma: no branch
        _ = m.cone(
            "mandible",
            jw,
            ho
            + V3((0.34 if viper else 0.3) * w * s, yb + 0.22 * hh, 0.08 * hl),
            ho + V3(0.07 * w * s, yb + 0.17 * hh, 0.88 * hl),
            0.14 * hh + 0.05 * w if viper else 0.11 * hh + 0.03 * w,
            0.1 * hh if viper else 0.085 * hh,
            k=0.003,
            part=JAW,
        )
    _ = m.ell(
        "jawfloor",
        jw,
        ho + V3(0, yb + 0.19 * hh, 0.46 * hl),
        V3(0.3 * w, 0.18 * hh, 0.42 * hl),
        k=0.003,
        part=JAW,
    )
    _ = m.sphere(
        "chin",
        jw,
        ho + V3(0, yb + 0.2 * hh, 0.9 * hl),
        0.14 * hh,
        k=0.003,
        part=JAW,
    )

    # The tongue and the fangs are dropped at the low and crowd tiers.
    if t.get("res") < 2.5:
        # TONGUE: two rigid pieces, the shaft and the forked tips.
        var tb = rig.j("tongueBase")
        var tf = rig.j("tongueFork")
        var tt = rig.j("tongueTip")
        var tr = 0.0007 * plan.kh * (1.25 if viper else 1.0)
        _ = m.cone(
            "tongue",
            rig.bone("tongue"),
            tb,
            tf + V3(0, 0, tr),
            tr * 1.1,
            tr * 0.85,
            k=0.0,
            part=TONGUE,
        )
        var fork_len = length(tt - tf)
        for s in [1.0, -1.0]:  # pragma: no branch
            _ = m.cone(
                "fork",
                rig.bone("tongueTip"),
                tf + V3(0, 0, -tr * 0.5),
                tt + V3(s * fork_len * 0.28, 0, 0),
                tr * 0.8,
                tr * 0.32,
                k=tr * 0.6,
                part=TONGUE,
            )
        # FANGS: hinged, folded back along the palate.
        if viper:
            var fb = rig.j("fangBase")
            var ft = rig.j("fangTip")
            for s in [1.0, -1.0]:  # pragma: no branch
                _ = m.cone(
                    "fang",
                    rig.bone("fang"),
                    fb + V3(0.2 * w * s, 0, 0),
                    ft + V3(0.2 * w * s, 0, 0),
                    0.0009 * plan.kh,
                    0.00015,
                    k=0.0,
                    part=TEETH,
                )

    # RATTLE: flattened, two-lobed bells, each overlapping the next.
    if viper:
        var last = rig.bone("spine" + String(SPINE - 1))
        var a = rig.j("v" + String(SPINE - 1))
        var b = rig.j("v" + String(SPINE))
        var d = normalize(b - a)
        var n_seg = Int(t.get("rattleSegs", Float64(RATTLE_SEGS)))
        var tip = hw_at[SPINE]
        var seg_l = (RATTLE_LEN / Float64(RATTLE_SEGS)) * t.get("girth")
        # A rattle has one segment in the young, five to eight later.
        for k in range(n_seg):
            var f = Float64(k) / Float64(max(1, RATTLE_SEGS - 1))
            var wk = tip * (1.35 - 0.3 * f)
            var c0 = b + d * (seg_l * (Float64(k) + 0.55))
            # A rattle rests on the ground, not in it.
            var c = V3(c0.x, max(c0.y, wk * 0.78 + 0.0003), c0.z)
            _ = m.ell(
                "rattle",
                last,
                c,
                V3(wk, wk * 0.78, seg_l * 0.62),
                axis=d,
                k=seg_l * 0.25,
                part=APPENDAGE,
            )
            _ = m.ell(
                "rattle",
                last,
                c + d * (seg_l * 0.35),
                V3(wk * 0.82, wk * 0.62, seg_l * 0.38),
                axis=d,
                k=seg_l * 0.2,
                part=APPENDAGE,
            )
        # The tail tip plugs into the button.
        var q = b + d * (-seg_l * 0.2)
        _ = m.ell(
            "button",
            last,
            V3(q.x, max(q.y, tip * 0.9 + 0.0003), q.z),
            V3(tip * 1.05, tip * 0.9, seg_l * 0.7),
            axis=d,
            k=0.0,
            part=APPENDAGE,
        )


def snake_look(t: Traits) -> EyeLook:
    """Return the snake's eye colors.

    The rattlesnake has a vertical slit in a bronze iris. The corn snake
    has a round pupil in an orange-brown iris, red in the amelanistic
    morph.

    Args:
        t: The individual.

    Returns:
        The look.
    """
    if t.variant == RATTLESNAKE:
        return EyeLook(
            V3(0.12, 0.1, 0.07),
            V3(0.33, 0.27, 0.19),
            V3(0.16, 0.13, 0.09),
            V3(0.2, 0.17, 0.12),
            0.5,
            4.0,
        )
    if Int(t.get("morph", 0.0)) == AMEL:
        return EyeLook(
            V3(0.35, 0.02, 0.03),
            V3(0.62, 0.06, 0.07),
            V3(0.4, 0.03, 0.04),
            V3(0.3, 0.12, 0.05),
            0.42,
            0.0,
        )
    return EyeLook(
        V3(0.2, 0.06, 0.02),
        V3(0.62, 0.22, 0.06),
        V3(0.16, 0.05, 0.02),
        V3(0.3, 0.12, 0.05),
        0.42,
        0.0,
    )


def _swatches() -> List[String]:
    return [
        String("ground"),
        "flank",
        "saddle",
        "lateral",
        "border",
        "belly",
        "check",
    ]


def _corn(morph: Int) -> List[Int]:
    # Colors sampled from reference photos in neutral light.
    if morph == OKEETEE:
        return [
            0xD6843F,
            0xE0A45E,
            0xB52F1C,
            0xA23421,
            0x100B09,
            0xECE4D2,
            0x141110,
        ]
    if morph == WILD:
        return [
            0xA68A6C,
            0xB89C7C,
            0x8A3A24,
            0x7C3A28,
            0x1D1512,
            0xE4DDCC,
            0x1A1715,
        ]
    if morph == AMEL:
        return [
            0xEB9656,
            0xF0B070,
            0xD9482A,
            0xD65A36,
            0xF2ECE0,
            0xF3EEE4,
            0xE8A070,
        ]
    if morph == ANERY:
        return [
            0xA9A6A2,
            0xBDBAB4,
            0x4A4847,
            0x55524F,
            0x151414,
            0xE6E4E0,
            0x161515,
        ]
    if morph == -1:
        # The juvenile's duller, browner coat.
        return [
            0x9C8672,
            0xAE9A86,
            0x6E2A1C,
            0x5E2A20,
            0x140E0C,
            0xE6E0D2,
            0x151211,
        ]
    return [
        0xC9763F,
        0xD99A5C,
        0xA8321F,
        0x983A26,
        0x1B1310,
        0xE9E2D2,
        0x171412,
    ]


def _corn_mark(morph: Int) -> V3:
    if morph == OKEETEE:
        return V3(0.006, 0.004, 0.004)
    if morph == WILD:
        return V3(0.013, 0.01, 0.009)
    if morph == AMEL:
        return V3(0.86, 0.82, 0.74)
    if morph == ANERY:
        return V3(0.01, 0.01, 0.01)
    if morph == -1:
        return V3(0.008, 0.006, 0.006)
    return V3(0.012, 0.009, 0.008)


def _tweak(c: V3, warm: Float64, light: Float64) -> V3:
    return V3(
        c.x * (1.0 + 0.1 * warm + light),
        c.y * (1.0 + 0.02 * warm + light),
        c.z * (1.0 - 0.1 * warm + light),
    )


def snake_palette(t: Traits) -> Palette:
    """Return one snake's palette: its morph, warmed, lightened and dulled.

    Corn snakes run from bright orange to duller, browner grounds. Wild
    diamondbacks run from pale gray through gray-brown to reddish brown,
    with bolder or fainter diamonds.

    Args:
        t: The individual.

    Returns:
        The palette, in linear light.
    """
    var warm = t.get("coatWarm", 0.0)
    var light = t.get("coatLight", 0.0)
    var out = Palette()
    if t.variant == RATTLESNAKE:
        var names: List[String] = [
            String("ground"),
            "flank",
            "diamond",
            "center",
            "edge",
            "blotch",
            "belly",
            "ringW",
            "ringB",
            "rattle",
        ]
        var hexes: List[Int] = [
            0x8A7560,
            0x9A846A,
            0x56422F,
            0x76604A,
            0xCDBD9C,
            0x5E4A38,
            0xE2D6BC,
            0xE6E0D4,
            0x1A1715,
            0xBFAE8C,
        ]
        for i in range(len(names)):  # pragma: no branch
            out.set(names[i], _tweak(srgb(hexes[i]), warm, light))
        var tone = clamp(t.get("tone", 0.0), -1.0, 1.0)
        var tgt = srgb(0x8F8C86) if tone < 0.0 else srgb(0x9A6A4E)
        var k = abs(tone) * 0.75
        for key in [String("ground"), "flank", "center"]:  # pragma: no branch
            var f = 1.08 if key == "flank" else 1.0
            out.set(key, mix3(out.get(key), tgt * f, k))
        out.set(
            "diamond",
            mix3(
                out.get("diamond"),
                srgb(0x4A4744) if tone < 0.0 else srgb(0x5A3526),
                k * 0.7,
            ),
        )
        for key in [
            String("ground"),
            "flank",
            "center",
            "edge",
        ]:  # pragma: no branch
            out.set(key, out.get(key) * (1.0 + 1.6 * light))
        var bk = t.get("blotch")
        out.set(
            "diamond",
            mix3(
                out.get("diamond"),
                out.get("ground"),
                clamp(0.3 - 0.3 * (bk - 1.0) / 0.18, 0.0, 0.55),
            ),
        )
        out.set("mark", V3(0.69, 0.6, 0.45))
        return out^
    var morph = Int(t.get("morph", 0.0))
    var plain = morph == NORMAL or morph == WILD
    var juv = t.juvenile() > 0.0 and plain
    var pick = -1 if juv else morph
    var names = _swatches()
    var hexes = _corn(pick)
    debug_assert(len(names) == len(hexes), "A palette needs one color per name")
    for i in range(len(names)):  # pragma: no branch
        out.set(names[i], _tweak(srgb(hexes[i]), warm, light))
    var dulled = morph == NORMAL or morph == OKEETEE
    if dulled:
        var d = clamp(t.get("dull", 0.0), 0.0, 0.7)
        out.set("ground", mix3(out.get("ground"), srgb(0xA68A6C), d))
        out.set("flank", mix3(out.get("flank"), srgb(0xB89C7C), d))
        out.set("saddle", mix3(out.get("saddle"), srgb(0x8E2C1C), d * 0.6))
    out.set("mark", _corn_mark(pick))
    return out^


def _rand(seed: Int, k: Int, j: Int) -> Float64:
    # One number of the pattern's layout: feature `k`, draw `j`.
    return ihash(k, j * 7919 + 13, seed + 9173)


def _feature(
    ds: Float64, du: Float64, a: Float64, bb: Float64, diamond: Bool
) -> Float64:
    # A diamond, or a rounded box, `a` long and `bb` wide.
    if diamond:
        var l1 = abs(ds) / a + abs(du) / bb
        return (l1 - 1.0) * (a * bb) / sqrt(a * a + bb * bb)
    var rr = min(a, bb) * 0.55
    return rect_distance(abs(ds) - (a - rr), abs(du) - (bb - rr)) - rr


def _seg2(px: Float64, py: Float64, pts: List[V3], w: List[Float64]) -> Float64:
    # The distance from a 2-D point to a polyline of varying width. Each
    # point's x and y are the plane's two coordinates.
    var best = 1e9
    # Its callers pass literal polylines of two points or more.
    for i in range(len(pts) - 1):
        var ax = pts[i].x
        var ay = pts[i].y
        var bx = pts[i + 1].x - ax
        var by = pts[i + 1].y - ay
        var l2 = bx * bx + by * by
        var f = clamp(
            ((px - ax) * bx + (py - ay) * by) / (l2 if l2 > 0.0 else 1e-12),
            0.0,
            1.0,
        )
        var dx = px - ax - bx * f
        var dy = py - ay - by * f
        var d = sqrt(dx * dx + dy * dy) - (w[i] + (w[i + 1] - w[i]) * f)
        best = min(best, d)
    return best


def _scales(
    sg: Float64, across: Float64, size: Float64, keel: Float64
) -> Float64:
    # The relief of overlapping scales as a shade: a rhombic lattice of
    # scales, each lighter at its free rear edge, with dark seams. A keel
    # adds a pale ridge down each scale.
    var q1 = (sg + across) / size
    var q2 = (sg - across) / size
    var f1 = q1 - floor(q1)
    var f2 = q2 - floor(q2)
    var seam = smoothstep(0.1, 0.0, min(min(f1, 1.0 - f1), min(f2, 1.0 - f2)))
    var rear = 0.5 * (f1 + f2)
    var ridge = smoothstep(0.12, 0.0, abs(f1 - f2)) * keel
    return 0.9 + 0.12 * rear - 0.16 * seam + 0.06 * ridge


def snake_paint(
    pal: Palette, t: Traits, tag: String, bone: String, s: CoatSample
) -> Paint:
    """Paint one vertex of a snake.

    The pattern is laid out in body coordinates: the arc along the spine
    from the occiput and the angle around the body from the dorsal
    midline, so it wraps the tube like the real one. The corn snake has
    red saddles with black borders, lateral blotches, a spear point on
    the crown, a stripe behind the eye, cream labials and a checkered
    belly. The rattlesnake has dark diamonds with pale edges, flank
    blotches, a dark mask between pale face stripes and a black and white
    ringed tail. Dorsal scales, wide ventral scutes and head plates shade
    the scales.

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
    var plan = _Plan(t)
    var viper = plan.viper
    var tongue = tag == "tongue" or tag == "fork"
    if tongue:
        var tc = srgb(0x141212) if viper else (
            srgb(0x1A0F0F) if tag == "fork" else srgb(0x5A1414)
        )
        return Paint(tc, WET)
    if tag == "fang":
        return Paint(srgb(0xECE4D0), KERATIN)
    var rattle = tag == "rattle" or tag == "button"
    if rattle:
        var rc = pal.get("rattle")
        var dark = V3(rc.x * 0.55, rc.y * 0.5, rc.z * 0.45)
        return Paint(mix3(rc, dark, 0.5 + 0.5 * sin(-p.z * 900.0)), KERATIN)
    var hl = plan.head_len
    var w = plan.head_w * plan.kh
    var hh = plan.head_h * plan.kh
    var kh = plan.kh
    var nz_f = fbm3(p * 60.0, 3) - 0.5
    var n_lo = fbm3(p * 9.0, 3) - 0.5
    if bone == "jaw":
        # The lower jaw: pale labials outside, the mouth lining inside.
        var mouth = n.y > 0.6 and p.y > 0.32 * hh and abs(p.x) < 0.12 * w
        if mouth:
            return Paint(srgb(0x8A5A58), SKIN)
        var jc = mix3(
            pal.get("edge"), pal.get("belly"), 0.5
        ) if viper else mix3(pal.get("belly"), pal.get("flank"), 0.3)
        var plate = 0.003 * kh if viper else 0.008 * kh
        jc = jc * _scales(-p.z, p.x, plate, 0.0) * (1.0 + 0.1 * n_lo)
        return Paint(jc, SCALES)

    var total = plan.body_len
    var s_vent = total * (1.0 - plan.tail_frac)
    var sg = -p.z
    var hw = plan.hw(clamp(max(0.0, sg) / total, 0.0, 1.0))
    var ya = hw * plan.flat
    var u = atan2(p.x, p.y - ya)
    var seed = Int(t.get("coatSeed", 0.0))
    var count = t.get("count")
    var bk = t.get("blotch")
    var belly = p.y < 0.1 * hw and n.y < -0.75 and sg > -0.2 * hl
    var lat = smoothstep(0.9, 2.2, abs(u))
    var col = mix3(pal.get("ground"), pal.get("flank"), lat)
    var pat = 1.0
    var pcol = col
    var mk = 1.0
    var size = (0.0042 if viper else 0.0024) * (
        hw / (0.0265 if viper else 0.0135)
    ) ** 0.35
    var keel = 0.85 if viper else 0.05
    var morph = Int(t.get("morph", 0.0))
    var bw = (
        2.6 if morph == OKEETEE else (1.2 if morph == AMEL else 1.0)
    ) * 0.0007
    var tailed = viper and sg > s_vent
    if tailed:
        # The coon tail: black and white rings from the vent to the rattle.
        var rl = (total - s_vent) / 9.5
        var q = (sg - s_vent) / rl
        col = pal.get("ringW")
        var f = q - floor(q)
        var odd = Int(floor(q)) % 2 == 1
        if odd:
            pat = -min(f, 1.0 - f) * rl
            pcol = pal.get("ringB")
        else:
            pat = min(f, 1.0 - f) * rl
        pat += nz_f * 0.0015
    elif viper:
        # Dark diamonds down the back, and flank blotches below their
        # lateral corners.
        var s_start = 0.045 * total
        var nf = Int(count * 29.0 + 0.5)
        var sp = (s_vent - s_start) / Float64(nf)
        var k0 = Int(floor((sg - s_start) / sp))
        for k in range(max(0, k0 - 1), min(nf, k0 + 2)):
            var fs = (
                s_start
                + (Float64(k) + 0.5) * sp
                + (_rand(seed, k, 0) - 0.5) * 0.08 * sp
            )
            var d = _feature(sg - fs, u * hw, 0.56 * sp, 0.9 * hw, True)
            d += nz_f * 0.0012
            if d < pat:
                pat = d
                pcol = mix3(
                    pal.get("diamond"),
                    pal.get("center"),
                    smoothstep(-0.003, -0.009, d) * 0.8,
                )
            for j in range(2):  # pragma: no branch
                var side = 1.0 if j == 0 else -1.0
                var bs = (
                    fs + 0.5 * sp + (_rand(seed, k, 1 + j) - 0.5) * 0.1 * sp
                )
                var db = _feature(
                    sg - bs, (u - side * 1.55) * hw, 0.2 * sp, 0.28 * hw, False
                )
                db += nz_f * 0.0012
                if db < pat:
                    pat = db
                    pcol = pal.get("blotch")
        # Pale diamond edges, one scale wide, fading into the ground.
        col = mix3(
            pal.get("edge"),
            col,
            smoothstep(0.0022, 0.0034, pat + 0.0006 * nz_f),
        )
    else:
        # Saddles with dark borders, lateral blotches between them, and
        # closer saddles down the tail.
        var s_start = max(0.0, 1.5 * hl - (0.5 * (s_vent - 1.5 * hl)) / 36.0)
        var nf = Int(count * 36.0 + 0.5)
        var sp = (s_vent - s_start) / Float64(nf)
        var k0 = Int(floor((sg - s_start) / sp))
        for k in range(max(0, k0 - 1), min(nf, k0 + 2)):
            var fs = (
                s_start
                + (Float64(k) + 0.5) * sp
                + (_rand(seed, k, 0) - 0.5) * 0.14 * sp
            )
            var a = (0.25 + 0.06 * _rand(seed, k, 1)) * sp * bk
            var b = (1.0 + 0.14 * _rand(seed, k, 2)) * bk
            var fu = (_rand(seed, k, 3) - 0.5) * 0.12
            var d = _feature(sg - fs, (u - fu) * hw, a, b * hw, False)
            d += nz_f * 0.0016
            if d < pat:
                pat = d
                pcol = pal.get("saddle")
            for j in range(2):  # pragma: no branch
                var side = 1.0 if j == 0 else -1.0
                if _rand(seed, k, 4 + 4 * j) >= 0.85:
                    continue
                var ls = (
                    fs + 0.5 * sp + (_rand(seed, k, 5 + 4 * j) - 0.5) * 0.2 * sp
                )
                var la = (0.15 + 0.05 * _rand(seed, k, 6 + 4 * j)) * sp * bk
                var lb = 0.3 + 0.08 * _rand(seed, k, 7 + 4 * j)
                var lu = side * (1.72 + 0.1 * _rand(seed, k, 12 + j))
                var dl = _feature(sg - ls, (u - lu) * hw, la, lb * hw, False)
                dl += nz_f * 0.0016
                if dl < pat:
                    pat = dl
                    pcol = pal.get("lateral")
        var nt = Int(11.0 * count + 0.5)
        var spt = (total * 0.985 - s_vent) / Float64(nt)
        var kt = Int(floor((sg - s_vent) / spt))
        for k in range(max(0, kt - 1), min(nt, kt + 2)):
            var fs = s_vent + (Float64(k) + 0.5) * spt
            var d = _feature(sg - fs, u * hw, 0.27 * spt * bk, 1.2 * hw, False)
            d += nz_f * 0.0016
            if d < pat:
                pat = d
                pcol = pal.get("saddle")
        mk = abs(pat) - bw * (0.8 + 0.4 * (0.5 + nz_f))
    var scute = total / (182.0 if viper else 215.0)
    var low = belly or abs(u) > 2.55
    if low:
        var e = 1.0 if belly else smoothstep(2.55, 2.75, abs(u))
        col = mix3(col, pal.get("belly"), e)
        if e > 0.5:
            pat = 1.0
            mk = 1.0
        var checked = belly and not viper
        if checked:
            # The checkerboard belly: blocks on alternating sides, scute
            # by scute, and two dark stripes under the tail.
            var best = 1.0
            var c0 = 0.09 * total
            var j0 = Int(floor((sg - c0) / scute))
            for j in range(max(0, j0 - 2), j0 + 2):
                var cs = c0 + Float64(j) * scute
                var skip = cs >= s_vent or _rand(seed, 1000 + j, 0) >= 0.5
                if skip:
                    continue
                var at = cs + scute * (0.4 + 0.2 * _rand(seed, 1000 + j, 1))
                var ca = scute * (0.45 + 0.5 * _rand(seed, 1000 + j, 2))
                var side = 1.0 if _rand(seed, 1000 + j, 3) < 0.5 else -1.0
                var cw = 0.3 + 0.25 * _rand(seed, 1000 + j, 4)
                var xc = side * hw * (0.2 + cw * 0.5)
                var d = rect_distance(
                    abs(sg - at) - ca, abs(p.x - xc) - hw * cw * 0.5
                )
                best = min(best, d)
            if sg > s_vent:
                best = min(best, abs(abs(p.x) - hw * 0.35) - hw * 0.14)
            if best < 1.0:
                pat = best + nz_f * 0.0006
                pcol = pal.get("check")
        if belly:
            size = scute
            keel = -1.0
    # The head: scales grow into large head plates over a head length.
    var hq = smoothstep(-0.1 * hl, 1.2 * hl, sg)
    var plated = not belly and sg < 1.2 * hl
    if plated:
        var plate = 0.0027 * kh if viper else 0.009 * kh
        size = size + (plate - size) * (1.0 - hq)
        keel = keel * (0.5 + 0.5 * hq if viper else 1.0)
    var upper = n.y > -0.15 and p.y > 0.35 * hw
    var e = snake_eye(t)
    var eye_c = eye_frame_of(e, HEAD_O, 1.0).c
    var ez = eye_c.z
    var ey = eye_c.y
    var corn_head = not viper and sg < 1.3 * hl
    if corn_head:
        # The spear point on the crown and nape, the bar between the
        # eyes, and the stripe behind the eye to the jaw angle.
        var d = 1.0
        if upper:
            var spear: List[V3] = [
                V3(0.0, ez + 0.003 * kh, 0),
                V3(0.06 * w, 0.4 * hl, 0),
                V3(0.11 * w, 0.0, 0),
                V3(0.14 * w, -0.35 * hl, 0),
                V3(0.1 * w, -0.75 * hl, 0),
            ]
            var spear_w: List[Float64] = [
                0.0006 * kh,
                0.0011 * kh,
                0.0013 * kh,
                0.0014 * kh,
                0.001 * kh,
            ]
            var bar: List[V3] = [
                V3(0.0, ez + 0.1 * e.r, 0),
                V3(eye_c.x * 0.85, ez + 0.4 * e.r, 0),
            ]
            var bar_w: List[Float64] = [0.0012 * kh, 0.0009 * kh]
            d = (
                min(
                    _seg2(abs(p.x), p.z, spear, spear_w),
                    _seg2(abs(p.x), p.z, bar, bar_w),
                )
                + nz_f * 0.0005
            )
        var side_head = abs(p.x) > 0.2 * w and sg < 0.1 * hl
        if side_head:
            var post: List[V3] = [
                V3(ez - 1.0 * e.r, ey - 0.3 * e.r, 0),
                V3(0.2 * hl, 0.45 * hh, 0),
                V3(0.02 * hl, 0.36 * hh, 0),
            ]
            var post_w: List[Float64] = [0.0009 * kh, 0.0012 * kh, 0.0009 * kh]
            d = min(d, _seg2(p.z, p.y, post, post_w) + nz_f * 0.0004)
        if d < pat:
            pat = d
            pcol = pal.get("saddle")
            # The head's thin marks keep a thin border, or a heavy
            # okeetee border would swallow them.
            mk = abs(d) - min(bw, 0.0007) * 0.9
    var viper_face = viper and sg < 0.3 * hl and abs(p.x) > 0.15 * w
    if viper_face:
        # The dark mask between a pale stripe in front of the eye and one
        # behind it, running down to the mouth.
        var mask: List[V3] = [
            V3(ez + 0.4 * e.r, ey, 0),
            V3(0.3 * hl, 0.5 * hh, 0),
            V3(0.05 * hl, 0.42 * hh, 0),
        ]
        var mask_w: List[Float64] = [0.0022 * kh, 0.0022 * kh, 0.0016 * kh]
        var dm = _seg2(p.z, p.y, mask, mask_w)
        if dm < 0.0:
            col = mix3(
                col, pal.get("diamond"), 0.75 * smoothstep(0.0, -0.0015, dm)
            )
        var pre: List[V3] = [
            V3(ez + 1.7 * e.r, ey + 1.1 * e.r, 0),
            V3(0.78 * hl, 0.62 * hh, 0),
            V3(0.66 * hl, 0.4 * hh, 0),
        ]
        var pre_w: List[Float64] = [0.0011 * kh, 0.0018 * kh, 0.0015 * kh]
        var post: List[V3] = [
            V3(ez - 0.5 * e.r, ey - 1.5 * e.r, 0),
            V3(0.3 * hl, 0.34 * hh, 0),
            V3(0.02 * hl, 0.26 * hh, 0),
        ]
        var post_w: List[Float64] = [0.0011 * kh, 0.002 * kh, 0.0016 * kh]
        mk = min(
            mk,
            min(
                _seg2(p.z, p.y, pre, pre_w),
                _seg2(p.z, p.y, post, post_w),
            )
            + nz_f * 0.0004,
        )
    if sg < 0.02 * hl:
        if viper:
            col = mix3(
                col,
                pal.get("edge"),
                0.8 * smoothstep(0.46 * hh, 0.34 * hh, p.y),
            )
        elif p.y < 0.48 * hh:
            # The labials: belly cream with thin, faint sutures.
            col = mix3(
                col,
                pal.get("belly"),
                0.7 * smoothstep(0.48 * hh, 0.38 * hh, p.y),
            )
            var lu = (p.z / hl - 0.12) / 0.11
            var labial = abs(p.x) > 0.3 * w and lu >= 0.0 and lu <= 8.0
            if labial:
                var f = abs(lu - floor(lu + 0.5))
                mk = min(mk, f * 0.11 * hl - 0.00008 * kh)
        # The palate, well inside the lips.
        var palate = (
            n.y < -0.6
            and p.y < 0.4 * hh
            and abs(p.x) < 0.15 * w
            and p.z > 0.12 * hl
            and not belly
        )
        if palate:
            return Paint(srgb(0x8A5A58), SKIN)
    # Low-frequency mottling.
    col = V3(
        col.x * (1.0 + 0.1 * n_lo),
        col.y * (1.0 + 0.1 * n_lo),
        col.z * (1.0 + 0.08 * n_lo),
    )
    var spot = smoothstep(0.0008, -0.0008, pat)
    col = mix3(col, pcol, spot)
    var line = smoothstep(0.0005, -0.0005, mk)
    col = mix3(col, pal.get("mark"), line)
    var across = u * hw
    if belly:
        # Wide ventral scutes: one transverse plate after another.
        var q = sg / scute
        var f = q - floor(q)
        col = col * (0.88 + 0.14 * f - 0.12 * smoothstep(0.08, 0.0, f))
    else:
        # The relief fades onto the smooth head plates.
        var relief = _scales(sg, across, size, keel)
        col = col * (1.0 + (relief - 1.0) * (0.35 + 0.65 * hq))
    return Paint(col, SCALES)
