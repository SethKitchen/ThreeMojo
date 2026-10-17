# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Bear paint matches the original noise coordinate arithmetic exactly."""

from extensions.animals.species.bear import (
    BELLY,
    CLAW_BASE,
    CLAW_TIP,
    CoatSample,
    EAR,
    EAR_INNER,
    FACE,
    FLANK,
    FUR,
    GRIZZLED,
    HEAD,
    KERATIN,
    LEG,
    MUZZLE,
    NOSE,
    Paint,
    Palette,
    SKIN,
    TIP,
    Traits,
    V3,
    _agouti,
    _body,
    _desat,
    _ear_joints,
    _face_desat,
    _head_local,
    _lock,
    clamp,
    cross,
    dot,
    exp,
    fbm3,
    grizzle,
    length,
    lerp,
    mirrored_blob,
    mix3,
    normalize,
    on_side,
    smoothstep,
    srgb,
    vnoise3,
)
from extensions.animals.species.bear import (
    bear_paint as actual_bear_paint,
    _paint_ear as actual_paint_ear,
    _paint_head as actual_paint_head,
    bear_palette,
)
from extensions.animals.species.bear import bear_eye, eye_frame_of, HEAD_O
from extensions.animals.kit import aperture_local
from extensions.sdf.distance import almond_distance
from extensions.animals.options import FEMALE, ADULT
from extensions.animals.parts import LIMB
from std.memory import bitcast
from std.testing import TestSuite, assert_equal


# These reference bodies retain origin/main 0ad03120 arithmetic.
# Keep their operation order; a shorter oracle can change compiler rounding.
# The references call each other, not the changed paint functions.
def _lid_distance(t: Traits, p: V3) -> Float64:
    # The distance from a point to the nearer eye's aperture rim, in the
    # aperture's plane, or far when the point is behind the eye.
    var e = bear_eye(t)
    var s = 1.0 if p.x > HEAD_O.x else -1.0
    var ef = eye_frame_of(e, HEAD_O, s)
    var q = aperture_local(e, ef, p)
    var de = abs(almond_distance(q.x, q.y, e.big_r, e.d))
    return de if q.z > -0.3 * e.r else 1.0


def _referencebear_paint(
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
        var face = _reference_paint_head(c, t, tag, bone, p, n, nz, nz2, off)
        if face.surface != FUR:
            return face
        col = face.color
        ag = ag3.y * 0.7
    elif bone.startswith("ear"):
        col = _reference_paint_ear(c, t, p, n, off)
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


def _reference_paint_ear(
    c: List[V3], t: Traits, p: V3, n: V3, off: Float64
) -> V3:
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


def _reference_paint_head(
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


def _equal(actual: V3, expected: V3) raises:
    assert_equal(
        bitcast[DType.uint64](actual.x), bitcast[DType.uint64](expected.x)
    )
    assert_equal(
        bitcast[DType.uint64](actual.y), bitcast[DType.uint64](expected.y)
    )
    assert_equal(
        bitcast[DType.uint64](actual.z), bitcast[DType.uint64](expected.z)
    )


def _check_case(which: Int) raises:
    var t = Traits(FEMALE, ADULT, 0)
    var pal = bear_palette(t)
    var n = V3(0, 0, -1)
    var ears = _ear_joints(t)
    for i in range(1, 1000):
        var p = V3(Float64(i) / 997.0, 0.8, 0.7)
        var off = Float64(i % 997)
        t.set("coatSeed", off)
        if which == 0:
            p = lerp(ears[0], ears[1], 0.8) + V3(Float64(i) / 99700.0, 0, 0)
            _equal(
                actual_paint_ear(pal.colors, t, p, n, off),
                _reference_paint_ear(pal.colors, t, p, n, off),
            )
        elif which == 1:
            _equal(
                actual_paint_head(
                    pal.colors, t, "fur", "head", p, n, 0.1, 0.2, off
                ).color,
                _reference_paint_head(
                    pal.colors, t, "fur", "head", p, n, 0.1, 0.2, off
                ).color,
            )
        else:
            var s = CoatSample(p, n, p, 0, 0, LIMB)
            _equal(
                actual_bear_paint(pal, t, "fur", "earL", s).color,
                _referencebear_paint(pal, t, "fur", "earL", s).color,
            )


def test_ear_noise_matches_original_sum_order() raises:
    _check_case(0)


def test_head_noise_matches_original_sum_order() raises:
    _check_case(1)


def test_coat_noise_matches_original_sum_order() raises:
    _check_case(2)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
